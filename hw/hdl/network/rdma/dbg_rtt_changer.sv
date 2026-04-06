import lynxTypes::*;

module dbg_rtt_changer (
    output logic[31:0]          dbg_rtt,
    output logic[31:0]          dbg_target_delay, 
    output logic[31:0]          dbg_cwnd,
    output logic[31:0]          dbg_packets_in_flight,
    output logic[31:0]          dbg_delay,

    input  logic                aclk,
    input  logic                aresetn,

    input  logic [31:0]         rtt,
    input  logic                ack_event,
    input  logic [31:0]         curr_clk,

    metaIntf.s                  s_req,
    metaIntf.m                  m_req
);

parameter MAX_INFLIGHT = 20;

typedef struct packed {
    logic [31:0] rtt_val;
    logic        ack_val;
    logic [7:0]  countdown;
} packet_entry_t;

packet_entry_t delay_fifo [MAX_INFLIGHT-1:0];
integer i;

logic [31:0] delayed_rtt;
logic        delayed_ack;
integer packet_index;
integer packet_count_at_index;

function [31:0] rtt_graph(input integer index);
    // simple example: sinusoidal-ish pattern
    case (index)
        0: rtt_graph = 2000;
        1: rtt_graph = 6000;
        2: rtt_graph = 7000;
        3: rtt_graph = 8000;
        4: rtt_graph = 16000;
        5: rtt_graph = 6000;
        default: rtt_graph = 4000;
    endcase
endfunction

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        delayed_rtt <= 0;
        delayed_ack <= 0;
        packet_index <= 0;
        packet_count_at_index <= 0;

        for (i=0; i<MAX_INFLIGHT; i=i+1) begin
            delay_fifo[i].rtt_val <= 0;
            delay_fifo[i].ack_val <= 0;
            delay_fifo[i].countdown <= 0;
        end
    end else begin
        delayed_rtt <= 0;
        delayed_ack <= 0;

        // Enqueue new RTT and ACK values
        if (ack_event) begin
            for (i=0; i<MAX_INFLIGHT; i=i+1) begin
                if (delay_fifo[i].countdown == 0 && delay_fifo[i].ack_val == 0) begin
                    delay_fifo[i].rtt_val <= rtt_graph(packet_index);
                    delay_fifo[i].ack_val <= 1;
                    delay_fifo[i].countdown <= rtt_graph(packet_index);
                    packet_count_at_index <= packet_count_at_index + 1;

                    if (packet_count_at_index >= 50) begin 
                        packet_index <= packet_index + 1; 
                        packet_count_at_index <= 0;
                    end

                    break;
                end
            end
        end

       for (i = 0; i < MAX_INFLIGHT; i=i+1) begin  
            if (delay_fifo[i].countdown > 0) begin
                delay_fifo[i].countdown <= delay_fifo[i].countdown - 1;

                if (delay_fifo[i].countdown == 1) begin
                    delayed_rtt <= delay_fifo[i].rtt_val;
                    delayed_ack <= delay_fifo[i].ack_val;
                    delay_fifo[i].ack_val <= 0;  
                end
            end
        end
    end
end


rdma_congestion_control inst_swift(
    .dbg_base_rtt(dbg_rtt),
    .dbg_target_delay(dbg_target_delay),
    .dbg_cwnd(dbg_cwnd),
    .dbg_packets_in_flight(dbg_packets_in_flight),
    .dbg_delay(dbg_delay),

    .aclk(aclk),
    .aresetn(aresetn),

    .rtt(rtt),
    .ack_event(ack_event),
    .curr_clk(curr_clk),

    .s_req(s_req),
    .m_req(m_req)
);

endmodule