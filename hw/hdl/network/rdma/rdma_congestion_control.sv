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
    input  logic                aclk,
    input  logic                aresetn,

    input  logic [31:0]         rtt,
    input  logic                ack_event,

    metaIntf.s                  s_req,
    metaIntf.m                  m_req
);

localparam integer RDMA_N_OST = RDMA_N_WR_OUTSTANDING;
localparam integer RDMA_OST_BITS = $clog2(RDMA_N_OST);

logic [31:0] base_rtt;
logic [31:0] target_delay;
logic [31:0] acc; // accumulated ACKs for avoiding division
logic [31:0] acc_next;
logic [31:0] ai = 1; // additive constant for increasing cwnd
logic [31:0] cwnd; // congestion window in number of packets
logic [31:0] cwnd_next;
logic [31:0] packets_in_flight; // number of packets currently in flight
logic [31:0] packets_in_flight_next;

metaIntf #(.STYPE(dreq_t)) queue_out ();

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        base_rtt <= 32'hFFFF_FFFF; // max value
        target_delay <= 16; // TODO: figure out a good value for this
        cwnd <= 32'd1;
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
                base_rtt <= rtt;    // rn using old rtt

            logic [31:0] delay;
            delay = (rtt > base_rtt) ? (rtt - base_rtt) : 32'd0;
           

            if (delay <= target_delay) begin
                acc_next = acc + ai;
                if (acc_next >= cwnd) begin
                    acc_next = acc_next - cwnd;
                    cwnd_next = cwnd + 1;
                end 
            end else begin  // RTT nominal
                logic [31:0] temp;
                logic [31:0] decrease;

                temp = delay - target_delay;
                decrease = (cwnd * temp) >> 10; // 1/1024 = beta/rtt_nominal rn


                if (decrease > (cwnd >> 1)) // rn max multiplicative decrease is 1/2
                    cwnd_next = cwnd >> 1;
                else 
                    cwnd_next = cwnd - decrease;

                if (cwnd_next == 0)
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

endmodule