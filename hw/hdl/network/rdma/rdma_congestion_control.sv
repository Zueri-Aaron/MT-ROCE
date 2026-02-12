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
    input  logic [31:0]         rtt,
    input  logic                ack_event,

    output logic [31:0]         cwnd,

    input  logic                aclk,
    input  logic                aresetn
);

logic [31:0] base_rtt;
logic [31:0] target_delay;
logic [31:0] acc; // accumulated ACKs for avoiding division
logic [31:0] ai = 1; // additive constant for increasing cwnd

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        base_rtt <= 32'hFFFF_FFFF; // max value
        target_delay <= 16; // TODO: figure out a good value for this
        cwnd <= 32'd1;
        acc <= 32'd0;
    end else if (ack_event) begin
        if (rtt < base_rtt)
            base_rtt <= rtt;

        logic [31:0] delay;
        if (rtt > base_rtt)
            delay = rtt - base_rtt;
        else
            delay = 0;

        if (delay <= target_delay) begin
            acc <= acc + ai;
            if (acc >= cwnd) begin
                acc <= acc - cwnd;
                cwnd <= cwnd + 1;
            end 
        end else begin  // RTT nominal
            logic [31:0] temp;
            logic [31:0] decrease;

            temp = delay - target_delay;
            decrease = (cwnd >> 10) * temp; // 1/1024 = beta/rtt_nominal rn

            if (decrease > (cwnd >> 1)) // rn max multiplicative decrease is 1/2
                cwnd <= cwnd >> 1;
            else 
                cwnd <= cwnd - decrease;

            if (acc > cwnd)
                acc <= cwnd;
        end
    end
end

