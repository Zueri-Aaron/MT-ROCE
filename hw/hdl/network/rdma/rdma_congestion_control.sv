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

    metaIntf.s                  s_req,
    metaIntf.m                  m_req
);

localparam integer RDMA_N_OST = RDMA_N_WR_OUTSTANDING;
localparam integer RDMA_OST_BITS = $clog2(RDMA_N_OST);

// fs_min_cwnd = 10, fs_max_cwnd = 1000, fs_range = 30% of base_rtt = 300, fs_alpha = 1056, fs_beta = -33.39
localparam integer cwnd_values[0:15] = {10, 14, 18, 25, 34, 46, 63, 86, 117, 158, 215, 293, 398, 541, 736, 1000}; //in log2 accuracy LUT
//{10, 13.5936, 18.4785, 25.1189, 34.1455, 46.4159, 63.0957, 85.7696, 116.591, 158.489, 215.443, 292.864, 398.107, 541.17, 735.642, 1000}
//{300.547, 248.838, 215.512, 177.81, 147.713, 122.309, 99.6535, 80.4814, 64.2372, 50.6208, 38.6286, 28.3022, 19.5425, 12.011, 5.53468, 0.00365209}
localparam logic[8:0] target_delay_LUT[0:15] = {9'd300, 9'd249, 9'd216, 9'd178, 9'd148, 9'd122, 9'd100, 9'd80, 9'd64, 9'd51, 9'd39, 9'd28, 9'd20, 9'd12, 9'd6, 9'd1}; // log2 accuracy LUT
// slopes = {51/4, 33/4, 38/7, 30/9, 26/12, 22/17, 20/23, 16/31, 13/41, 12/57, 11/78, 8/105, 8/143, 6/195, 6/264}
localparam logic[11:0] slope_target_delay_LUT[0:14] = {12'd3264, 12'd2112, 12'd1390, 12'd853, 12'd555, 12'd331, 12'd223, 12'd132, 12'd81, 12'd54, 12'd36, 12'd20, 12'd14, 12'd8, 12'd6}; // log2 accuracy LUT
integer i;

//cwnd = cwnd - cwnd * (delay - target_delay) / delay => decrease = cwnd * (delay - target_delay) / delay = (delay - target_delay) * cwnd / delay
//K = cwnd / delay => cwnd / target_delay (approx of dela, will see how bad it gets). take mid_points of cwnd_i and target_delay_i to approximate this term:
//new decision: split cwnd and target_delay, thus adding 1 more multiplication but making the range of the number much smaller

// precision is /2048
//{6.82667, 8.2249, 9.48148, 11.5056, 13.8378, 16.7869, 20.48, 25.6, 32, 40.96, 52.5128, 73.1429, 102.4, 170.667, 341.333}
localparam integer decrease_factor_LUT[0:14] = {7, 8, 9, 12, 14, 17, 20, 26, 32, 41, 53, 73, 102, 171, 341}; // = 1/target_delay

localparam MIN_DELAY = 16;

integer seg_idx;
logic [31:0] base_rtt;
logic [31:0] target_delay;
logic [31:0] acc; // accumulated ACKs for avoiding division
logic [31:0] acc_next;
logic [31:0] ai = 1; // additive constant for increasing cwnd
logic [31:0] cwnd; // congestion window in number of packets
logic [31:0] cwnd_next;
logic [31:0] packets_in_flight; // number of packets currently in flight
logic [31:0] packets_in_flight_next;
logic [31:0] delay; 
logic [31:0] temp;
logic [31:0] decrease;
logic [50:0] mult;
logic [40:0] scaled;
logic [35:0] scaled_shifted;
logic found;

metaIntf #(.STYPE(dreq_t)) queue_out ();

always_comb begin
    target_delay = target_delay_LUT[15]; // if no match, use the last value in the LUT
    seg_idx = 15;
    found = 1'b0;
    for (i=1; i<16; i=i+1) begin
        if (cwnd < cwnd_values[i] && !found) begin
            target_delay = target_delay_LUT[i-1] - ((cwnd - cwnd_values[i-1]) * slope_target_delay_LUT[i-1] >> 8);
            seg_idx = i-1;
            found = 1'b1;
        end
    end
end

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        base_rtt <= 32'hFFFF_FFFF; // max value
        cwnd <= 32'd10;
        acc <= 32'd0;
        packets_in_flight <= 32'd0;
        m_req.valid <= 1'b0;
        queue_out.ready <= 1'b0;
        m_req.data <= 0;
    end else begin 
        packets_in_flight_next = packets_in_flight;
        cwnd_next = cwnd;
        acc_next = acc;

        if (ack_event) begin
            packets_in_flight_next = (packets_in_flight_next > 0) ? packets_in_flight_next - 1 : 0;
            if (rtt < base_rtt)
                base_rtt <= rtt;    
            delay = (rtt > base_rtt) ? (rtt - base_rtt) : 32'd0;
            if (delay < MIN_DELAY)
                delay = MIN_DELAY;
           

            if (delay <= target_delay) begin
                acc_next = acc + ai;
                if (acc_next >= cwnd) begin
                    acc_next = acc_next - cwnd;
                    cwnd_next = cwnd + 1;
                end 
            end else begin  // RTT nominal
                if (seg_idx == 15) begin
                    decrease = cwnd >> 1;
                end else begin
                    temp = delay - target_delay;
                    scaled = temp * decrease_factor_LUT[seg_idx]; 
                    //scaled_shifted = scaled >> 5; // early shift to reduce width
                    mult = (scaled * cwnd); 
                    decrease = mult >> 11;
                end

                if (decrease > (cwnd >> 1)) // rn max multiplicative decrease is 1/2
                    cwnd_next = cwnd >> 1;
                else 
                    cwnd_next = cwnd - decrease;

                if (cwnd_next < 1)
                    cwnd_next = 1;

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