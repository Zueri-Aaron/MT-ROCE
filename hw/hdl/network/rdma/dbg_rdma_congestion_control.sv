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

localparam integer cwnd_values[0:15] = {10, 14, 18, 25, 34, 46, 63, 86, 117, 158, 215, 293, 398, 541, 736, 1000}; //in log2 accuracy LUT
localparam logic[8:0] target_delay_LUT[0:15] = {9'd300, 9'd249, 9'd216, 9'd178, 9'd148, 9'd122, 9'd100, 9'd80, 9'd64, 9'd51, 9'd39, 9'd28, 9'd20, 9'd12, 9'd6, 9'd1}; // log2 accuracy LUT
localparam logic[11:0] slope_target_delay_LUT[0:14] = {12'd3264, 12'd2112, 12'd1390, 12'd853, 12'd555, 12'd331, 12'd223, 12'd132, 12'd81, 12'd54, 12'd36, 12'd20, 12'd14, 12'd8, 12'd6}; // log2 accuracy LUT
integer i;

localparam integer decrease_factor_LUT[0:15] = {7, 8, 9, 12, 14, 17, 20, 26, 32, 41, 53, 73, 102, 171, 341}; // = 1/target_delay

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

always_comb begin
    target_delay = target_delay_LUT[15]; // if no match, use the last value in the LUT
    seg_idx = 15;
    for (i=1; i<16; i=i+1) begin
        if (cwnd < cwnd_values[i]) begin
            target_delay = target_delay_LUT[i-1] + ((cwnd - cwnd_values[i-1]) * slope_target_delay_LUT[i-1] >> 8);
            seg_idx = i-1;
            break;
        end
    end
end

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