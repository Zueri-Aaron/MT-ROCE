`timescale 1ns/1ps
`include "dbg_metaIntf.sv"
import lynx_min_pkg::*;

module dbg_network_model #(
    parameter integer MAX_INFLIGHT = 64
)(
    input  logic        aclk,
    input  logic        aresetn,

    // input from RDMA (requests going to network)
    dbg_metaIntf.s      m_req,

    // output back to RDMA (ACKs coming from network)
    dbg_metaIntf.m      s_ack,

    input  logic [31:0] curr_clk,
    input  logic [31:0] load,
    input  logic        incast_active
);

    typedef struct packed {
        dreq_t      req;
        longint unsigned ack_time;
    } net_pkt_t;

    net_pkt_t fifo[$];   // simple SystemVerilog queue
    localparam integer MAX_INFLIGHT_BYTES = 64 * 4 * 1024;
    localparam integer MAX_QUEUE_MEMORY = 1024;


    logic ack_valid_r;
    ack_t ack_data_r;
    int unsigned inflight_bytes;
    int signed delta_inflight;
    logic [31:0] background_load;

    localparam int BASE_RTT_CYCLES = 1000;
    localparam int LINK_BITS_PER_CYCLE = 400; // 100Gb/s @ 4ns



    longint unsigned next_link_free;
    int unsigned time_in_queue;
    int unsigned effective_link_bits_per_cycle;

    assign s_ack.valid = ack_valid_r;
    assign s_ack.data.ack = ack_data_r;
    assign s_ack.data.last = 1'b1;

    assign m_req.ready = (inflight_bytes < MAX_INFLIGHT_BYTES);

    logic fire_req;
    logic fire_ack;

    assign fire_req = m_req.valid && m_req.ready;
    assign fire_ack = s_ack.valid && s_ack.ready;

    assign background_load = load * MAX_INFLIGHT_BYTES / 100; // tweak

    int unsigned queue_bytes;
    logic [31:0] queue_memory;

    // model queue persistence
    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            queue_memory <= 0;
        end else begin

            // queue buildup
            if ((inflight_bytes + background_load) > MAX_INFLIGHT_BYTES/2) begin
                if (queue_memory + 8 > MAX_QUEUE_MEMORY) begin
                    queue_memory <= MAX_QUEUE_MEMORY;
                end else begin
                    queue_memory <= queue_memory + 8;
                end
            end
            // queue draining
            else if (queue_memory > 0) begin
                queue_memory <= queue_memory - 1;
            end
        end
    end

    // ----------------------------
    // helper: generate delay
    // ----------------------------
    function int unsigned gen_delay();
        int unsigned queue_occupancy;
        int unsigned queue_penalty;
        int unsigned jitter;

        queue_occupancy = ((inflight_bytes + background_load) * 25) / MAX_INFLIGHT_BYTES;

        // nonlinear congestion growth
        queue_penalty = (queue_occupancy * queue_occupancy) * 2 + queue_memory;

        if (incast_active) begin
            queue_penalty = queue_penalty * 2;;
        end

        jitter = $urandom % (50 + queue_occupancy * 4);

        return 1000 + queue_penalty + jitter;
    endfunction

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            fifo.delete();

            ack_valid_r <= 0;
            ack_data_r  <= '0;

            inflight_bytes <= 0;
        end
        else begin
            delta_inflight = 0;

            // ----------------------------
            // outgoing requests
            // ----------------------------
            if (fire_req) begin
                net_pkt_t p;

                longint unsigned tx_start;
                longint unsigned tx_finish;
                int unsigned serialization_cycles;
                int unsigned jitter;
                int unsigned queue_delay;

                jitter = $urandom_range(0,20);

                effective_link_bits_per_cycle = LINK_BITS_PER_CYCLE * (100 - load) / 100;

                serialization_cycles = ((m_req.data.req_1.len * 8) + effective_link_bits_per_cycle - 1) / effective_link_bits_per_cycle;

                tx_start = (curr_clk > next_link_free) ? curr_clk : next_link_free;

                tx_finish = tx_start + serialization_cycles;

                time_in_queue = tx_finish - curr_clk;

                next_link_free <= tx_finish;

                p.req       = m_req.data;
                p.ack_time = tx_finish + BASE_RTT_CYCLES + jitter;

                fifo.push_back(p);

                delta_inflight = delta_inflight + m_req.data.req_1.len;
            end

            // ----------------------------
            // ACK 
            // ----------------------------
            if (fire_ack) begin
                ack_valid_r <= 0;

                delta_inflight = delta_inflight - fifo[0].req.req_1.len;

                fifo.pop_front();
            end

            if (!ack_valid_r && fifo.size() > 0) begin
                net_pkt_t p;

                p = fifo[0];

                if (curr_clk >= p.ack_time) begin
                    ack_valid_r <= 1;

                    ack_data_r.vfid <= p.req.req_1.vfid;
                    ack_data_r.pid  <= p.req.req_1.pid;
                    ack_data_r.opcode <= RC_ACK;


                end
            end
            inflight_bytes <= inflight_bytes + delta_inflight;
        end
    end
    
endmodule