/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

//MT zaaron implementation of SWIFT
import lynxTypes::*;

module rdma_congestion_control (
    output logic [31:0]         dbg_base_rtt,
    output logic [31:0]         dbg_target_delay,
    output logic [31:0]         dbg_cwnd,
    output logic [31:0]         dbg_packets_in_flight,
    output logic [31:0]         dbg_delay,

    input  logic                aclk,
    input  logic                aresetn,

    input  logic [31:0]         rtt,
    input  logic                ack_event,
    input  logic [31:0]         curr_clk,

    metaIntf.s                  s_req,
    metaIntf.m                  m_req
);

localparam integer RDMA_N_OST = RDMA_N_WR_OUTSTANDING;
localparam integer RDMA_OST_BITS = $clog2(RDMA_N_OST);
localparam logic[4:0] MAX_CWND = 16;

// fs_min_cwnd = 1, fs_max_cwnd = 16, fs_range = 25% of base_rtt, fs_alpha = 4/3 * fs_range, fs_beta = - 1/3 * fs_range

//{1024, 624.103, 446.942, 341.333, 269.262, 216.062, 174.714, 141.385, 113.778, 90.423, 70.3302, 52.8045, 37.342, 23.5673, 11.1942, 0}
localparam logic[9:0] target_delay_LUT[0:15] = {256, 156, 112, 85, 67, 54, 44, 35, 28, 23, 18, 13, 9, 6, 3, 1};
//{1024, 659.673, 498.27, 402.055, 336.394, 287.925, 250.256, 219.891, 194.739, 173.462, 155.156, 139.189, 125.102, 112.553, 101.28, 91.0818, 81.7969, 73.297, 65.4772, 58.2515, 51.5483, 45.3075, 39.4783, 34.0172, 28.8873, 24.0562, 19.496, 15.1824, 11.0938, 7.21145, 3.51848, 0}
//localparam logic[9:0] target_delay_LUT[0:31] = {10'd1024, 10'd660, 10'd498, 10'd402, 10'd336, 10'd288, 10'd250, 10'd220, 10'd195, 10'd173, 10'd155, 10'd139, 10'd125, 10'd113, 10'd101, 10'd91, 10'd82, 10'd73, 10'd65, 10'd58, 10'd52, 10'd45, 10'd39, 10'd34, 10'd29, 10'd24, 10'd19, 10'd15, 10'd11, 10'd7, 10'd4, 10'd1}; // log2 accuracy LUT

localparam logic[3:0] precision = 10;
//cwnd = cwnd - cwnd * (delay - target_delay) / delay => decrease = cwnd * (delay - target_delay) / delay = (delay - target_delay) * cwnd / delay
//K = cwnd / delay => cwnd / target_delay (approx of dela, will see how bad it gets). take mid_points of cwnd_i and target_delay_i to approximate this term:
//new decision: split cwnd and target_delay, thus adding 1 more multiplication but making the range of the number much smaller

//beta = 0.3
//{0.001, 0.00164075, 0.00229113, 0.003, 0.00380299, 0.00473939, 0.005861, 0.00724263, 0.00900001, 0.0113246, 0.0145599, 0.0193922, 0.0274223, 0.0434499, 0.0914757, 0.3}
// precision is /1024
//{1.024, 1.68013, 2.34612, 3.072, 3.89426, 4.85314, 6.00166, 7.41645, 9.21601, 11.5964, 14.9093, 19.8576, 28.0804, 44.4927, 93.6711, 307.2}
localparam logic[9:0] decrease_factor_LUT[0:15] = {10'd1, 10'd2, 10'd2, 10'd3, 10'd4, 10'd5, 10'd6, 10'd7, 10'd9, 10'd11, 10'd15, 10'd19, 10'd27, 10'd43, 10'd91, 10'd256}; // = beta/target_delay
//{1.024, 1.58954, 2.10443, 2.60804, 3.11711, 3.64183, 4.19002, 4.76862, 5.38451, 6.04499, 6.75819, 7.53344, 8.38175, 9.31629, 10.3532, 11.5125, 12.8193, 14.3059, 16.0144, 18.0008, 20.3416, 23.1435, 26.5608, 30.8248, 36.2989, 43.5887, 53.7842, 69.0654, 94.5189, 145.404, 298.02, ∞}
//localparam logic[9:0] decrease_factor_LUT[0:31] = {10'd1, 10'd2, 10'd2, 10'd3, 10'd3, 10'd4, 10'd4, 10'd5, 10'd5, 10'd6, 10'd7, 10'd8, 10'd8, 10'd9, 10'd10, 10'd12, 10'd13, 10'd14, 10'd16, 10'd18, 10'd20, 10'd23, 10'd27, 10'd31, 10'd36, 10'd44, 10'd54, 10'd69, 10'd95, 10'd145, 10'd298, 10'd307}; // = beta/target_delay
// this currently assumes base_rtt = 1000. Change maybe later in MT

logic [31:0] base_rtt;
logic [31:0] target_delay;
logic [7:0] target_delay_factor;
logic [31:0] acc; // accumulated ACKs for avoiding division
logic [31:0] acc_next;
logic [31:0] cwnd; // congestion window in number of packets
logic [31:0] cwnd_next;
logic [31:0] packets_in_flight; // number of packets currently in flight
logic [31:0] packets_in_flight_next;
logic [31:0] delay; 
logic [3:0] cwnd_index;

logic [31:0] delta;
logic [41:0] mult1;
logic [46:0] mult2;
logic [31:0] decrease;

logic [31:0] last_decrease;

metaIntf #(.STYPE(dreq_t)) queue_out ();

always_comb begin
    cwnd_index = (cwnd > 15) ? 4'd15 : cwnd[3:0] - 1;
    target_delay_factor = target_delay_LUT[cwnd_index]; 
    target_delay = (target_delay_factor * base_rtt) >> precision;
    
    delay = (rtt > base_rtt) ? (rtt - base_rtt) : 32'd0;
end

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        base_rtt <= 32'hFFFF_FFFF; // max value
        cwnd <= 32'd1;
        acc <= 32'd0;
        packets_in_flight <= 32'd0;
        m_req.valid <= 1'b0;
        queue_out.ready <= 1'b0;
        m_req.data <= 0;
        last_decrease <= 0;
    end else begin 
        packets_in_flight_next = packets_in_flight;
        cwnd_next = cwnd;
        acc_next = acc;

        if (ack_event) begin
            packets_in_flight_next = (packets_in_flight_next > 0) ? packets_in_flight_next - 1 : 0;
            if (rtt < base_rtt)
                base_rtt <= rtt;    

            if (delay <= target_delay) begin
                acc_next = acc + 1;
                if (acc_next >= cwnd) begin
                    acc_next = acc_next - cwnd;
                    if (cwnd != 32)
                        cwnd_next = cwnd + 1;
                end 
            end else if (rtt < (curr_clk) - last_decrease) begin 
                delta = delay - target_delay;
                mult1 = delta * decrease_factor_LUT[cwnd_index];
                mult2 = mult1 * cwnd[4:0]; 
                decrease = mult2 >> precision;

                if (decrease > (cwnd >> 1)) // rn max multiplicative decrease is 1/2
                    cwnd_next = cwnd >> 1;
                else 
                    cwnd_next = cwnd - decrease;

                if (cwnd_next < 1)
                    cwnd_next = 1;

                if (cwnd_next < cwnd)
                    last_decrease <= curr_clk;

                if (acc_next > cwnd_next)
                    acc_next = cwnd_next;
            end
        end

        //congestion window logic
        m_req.valid <= 1'b0;
        m_req.data <= queue_out.data;
        queue_out.ready <= 1'b0;

        if (packets_in_flight_next < cwnd_next) begin
            m_req.valid <= queue_out.valid;
            queue_out.ready <= m_req.ready;
            if (queue_out.valid && m_req.ready) begin
                packets_in_flight_next = packets_in_flight_next + 1;
            end
        end
        packets_in_flight <= packets_in_flight_next;
        cwnd <= cwnd_next;
        acc <= acc_next;
    end

    
end

queue_meta #(
    .QDEPTH(RDMA_N_OST)
) inst_cq (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_meta(s_req),
    .m_meta(queue_out)
);

assign dbg_base_rtt          = base_rtt;
assign dbg_target_delay      = target_delay;
assign dbg_cwnd              = cwnd;
assign dbg_packets_in_flight = packets_in_flight;
assign dbg_delay             = delay;

endmodule