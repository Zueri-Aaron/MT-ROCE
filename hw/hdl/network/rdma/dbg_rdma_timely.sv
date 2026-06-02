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

//MT zaaron implementation of TIMELY
`include "dbg_metaIntf.sv"
import lynx_min_pkg::*;

module dbg_rdma_timely (
    output logic [31:0]         dbg_base_rtt,
    output logic [31:0]         dbg_target_delay,
    output logic [31:0]         dbg_cwnd,
    output logic [31:0]         dbg_packets_in_flight,
    output logic [31:0]         dbg_delay,
    output logic                dbg_m_req_ready,
    output logic                dbg_queue_out_valid,
    output logic                dbg_can_send,
    output logic                fire_dbg,

    input  logic                aclk,
    input  logic                aresetn,

    input  logic [31:0]         rtt,
    input  logic                ack_event,
    input  logic [31:0]         curr_clk,

    dbg_metaIntf.s                  s_req,f
    dbg_metaIntf.m                  m_req
);

typedef struct packed {
    logic [31:0]    clk;
    logic [11:0]    rtt;
} swift_ack_tx_t;

localparam integer RDMA_N_OST = RDMA_N_WR_OUTSTANDING;
localparam integer RDMA_OST_BITS = $clog2(RDMA_N_OST);

dbg_metaIntf #(.STYPE(dreq_t)) queue_out ();

//snapshot variables
swift_ack_tx_t ack_fifo[0:RDMA_N_OST-1];
logic [RDMA_OST_BITS-1:0] ack_fifo_head, ack_fifo_tail;
logic [RDMA_OST_BITS:0] ack_fifo_count;

//pipeline
logic pipe_busy;
logic fifo_ready;

//parameters
//alpha ewma = 1/8
localparam integer PRECISION = 10;
localparam integer alpha_ewma = 3; // 2^3 = 8
localparam integer fire_threshold = 2 << PRECISION; // 2^10 = precision
localparam integer min_RTT_shift = 10;
localparam integer min_RTT = 2 << min_RTT_shift; // 2^10 = 1024 cycles = 1us, with 1GHz clock, should be safe for 100Gbps



//stuff
logic signed [31:0] rate;
logic signed [31:0] threshold_rate;


logic [11:0] prev_rtt;
logic signed [12:0] new_rtt_diff;
logic [11:0] queue_delay;

logic stage1;
logic signed [15:0] rtt_diff;

logic stage2;
logic signed [31:0] stage2_rate;

logic stage3;
logic signed [31:0] normalized_gradient;
logic signed [31:0] rate_decrease;

logic [4:0] consecutive_increase_count;

assign pipe_busy = stage1 || stage2 || stage3;
assign fifo_ready = (ack_fifo_count > 0);


always_ff @(posedge aclk) begin
    if (!aresetn) begin
        ack_fifo_head <= 0;
        ack_fifo_tail <= 0;
        ack_fifo_count <= 0;

        curr_delay <= 0;
        curr_rtt <= 0;
        clk_stage0 <= 0;
        stage0 <= 0;
    end else if (ack_event && ack_fifo_count < RDMA_N_OST) begin
        ack_fifo[ack_fifo_tail].rtt <= rtt[11:0];
        ack_fifo[ack_fifo_tail].clk <= curr_clk;

        ack_fifo_tail <= ack_fifo_tail + 1;
        ack_fifo_count <= ack_fifo_count + 1;
        stage0 <= 0;
    end else if (!pipe_busy && fifo_ready) begin
        // dequeue ack event into pipeline
        curr_rtt <= ack_fifo[ack_fifo_head].rtt;

        ack_fifo_head <= ack_fifo_head + 1;
        ack_fifo_count <= ack_fifo_count - 1;
        stage0 <= 1;
    end else begin
        stage0 <= 0;
    end
end

//stage 0
always_ff @(posedge aclk) begin
    if (!aresetn) begin
        prev_rtt <= 0;
        stage1 <= 0;
    end else if (stage0) begin
        new_rtt_diff <= $signed(curr_rtt) - $signed(prev_rtt);
        prev_rtt <= curr_rtt;
        queue_delay <= (curr_rtt > min_RTT) ? (curr_rtt - min_RTT) : 0;
        stage1 <= 1;
    end else begin
        stage1 <= 0;
    end
end

//stage 1
always_ff @(posedge aclk) begin
    if (!aresetn) begin
        stage2 <= 0;
        rtt_diff <= 0;
    end else if (stage1) begin
        rtt_diff <= (rtt_diff - (rtt_diff >>> alpha_ewma)) + (new_rtt_diff >>> alpha_ewma); // = rtt_diff * (7/8) + new_rtt_diff * (1/8)
        stage2 <= 1;
    end else begin
        stage2 <= 0;
    end
end

//stage 2
always_ff @(posedge aclk) begin
    if (!aresetn) begin
        stage3 <= 0;
        normalized_gradient <= 0;
        rate_decrease <= 0;
        stage2_rate <= 1;
    end else if (stage2) begin
        normalized_gradient <=  rtt_diff;  // = (rtt_diff << PRECISION) >>> min_RTT_shift;
        rate_decrease <= rtt_diff >>> 1; // 

        stage2_rate <= rate;
        if (queue_delay < T_low) begin
            stage2_rate <= rate + increase_factor;
        end else if (queue_delay > T_high) begin
            stage2_rate <= rate >> 1; // quick fix, want to test gradient anyways
        end

        stage3 <= 1;
    end else begin
        stage3 <= 0;
    end
end

//stage 3
always_ff @(posedge aclk) begin
    if (!aresetn) begin
        rate <= 1;
        consecutive_increase_count <= 0;
    end else if (stage3) begin
        
        if (normalized_gradient > 0) begin
            rate <= rate_decrease > stage2_rate ? 1 : stage2_rate - rate_decrease;
            consecutive_increase_count <= 0;
        end else begin
            if (consecutive_increase_count >= 5) begin
                rate <= stage2_rate + (increase_factor << 2);
            end else begin
                rate <= stage2_rate + increase_factor;
            end
            consecutive_increase_count <= consecutive_increase_count >= 5 ? 5 : consecutive_increase_count + 1;
        end
    end
end


logic can_send;
assign can_send = (threshold_rate >= fire_threshold);;

assign m_req.valid = can_send && queue_out.valid;
assign queue_out.ready = can_send && m_req.ready;
assign m_req.data = queue_out.data;

logic fire;
assign fire = m_req.valid && m_req.ready;
 
logic [4:0] inflight_next;

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        threshold_rate <= (2 << PRECISION); 
    end else begin
    
        if (fire) begin
            threshold_rate <= threshold_rate - fire_threshold + rate;
        end else begin
            threshold_rate <= threshold_rate + rate;
        end
    end
end

dbg_queue_meta #(
    .QDEPTH(RDMA_N_OST)
) inst_sq (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_meta(s_req),
    .m_meta(queue_out)
);


assign dbg_base_rtt          = 0;
assign dbg_target_delay      = 0;
assign dbg_cwnd              = rate;
assign dbg_packets_in_flight = threshold_rate;
assign dbg_delay             = 0;
assign dbg_m_req_ready       = m_req.ready;
assign dbg_queue_out_valid   = queue_out.valid;
assign dbg_can_send           = can_send;
assign fire_dbg               = fire;

endmodule