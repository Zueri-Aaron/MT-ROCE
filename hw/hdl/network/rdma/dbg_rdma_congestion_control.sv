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


module dbg_rdma_congestion_control (
    input  logic [31:0]         rtt,
    input  logic                ack_event,

    input  logic                aclk,
    input  logic                aresetn,

    output logic                dummy_out
);

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



always_ff @(posedge aclk) begin
    if (!aresetn) begin
        base_rtt <= 32'hFFFF_FFFF; // max value
        target_delay <= 32'd1000; // rn we had about 1000 cycles at 4 GHz
        cwnd <= 32'd1;
        acc <= 32'd0;
        packets_in_flight <= 32'd0;
        dummy_out <= 1'b0;
    end else begin 
        packets_in_flight_next = packets_in_flight;
        cwnd_next = cwnd;
        acc_next = acc;

        if (ack_event) begin
            packets_in_flight_next = (packets_in_flight_next > 0) ? packets_in_flight_next - 1 : 0;
            if (rtt < base_rtt) begin
                base_rtt <= rtt;    // rn using old rtt
            end
            
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
        dummy_out <= 1'b0;

        if (packets_in_flight_next < cwnd_next) begin
            dummy_out <= 1'b1;
            packets_in_flight_next = packets_in_flight_next + 1;
        end
        packets_in_flight <= packets_in_flight_next;
        cwnd <= cwnd_next;
        acc <= acc_next;
    end

    
end

endmodule