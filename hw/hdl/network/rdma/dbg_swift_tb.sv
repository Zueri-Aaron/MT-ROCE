`timescale 1ns/1ps

`include "dbg_metaIntf.sv"
import lynx_min_pkg::*;

module dbg_swift_tb;
    logic [31:0]         dbg_base_rtt;
    logic [31:0]         dbg_target_delay;
    logic [31:0]         dbg_cwnd;
    logic [31:0]         dbg_packets_in_flight;
    logic [31:0]         dbg_delay;
    logic                dbg_can_send;
    logic                fire_dbg;
    logic dbg_m_req_ready;
    logic dbg_queue_out_valid;


    logic [31:0] rtt;
    logic [31:0] curr_clk;
    logic aclk;
    logic aresetn;
    logic [31:0] background_load;
    
    dbg_metaIntf #(.STYPE(dreq_t)) s_req();
    dbg_metaIntf #(.STYPE(dreq_t)) m_req();
    
    dbg_metaIntf #(.STYPE(dack_t))  s_ack();
    dbg_metaIntf #(.STYPE(ack_t))   m_ack();
    
    dreq_t wr_req;

    logic [31:0] fifo_time [0:15];
    logic [3:0] fifo_head, fifo_tail;
    logic [4:0] fifo_count;

    localparam integer bytes_per_packet = 4096;
    localparam integer startup_packets = 100; 
    localparam integer number_of_packets = 10000;

    localparam integer compute_phase_packets = 2;
    localparam integer sync_phase_packets = 20;
    localparam integer recovery_phase_packets = 5;

    integer number_of_successful_transfers;
    integer packets_sent;
    integer difference_at_start_of_recovery;

    phase_t phase;
    logic [31:0] phase_timer;
    logic incast_active;
    integer send_credits;


    // Clock: 100 MHz
    initial aclk = 0;
    always #5 aclk = ~aclk;


    always_ff @(posedge aclk) begin
        if(!aresetn)
            curr_clk <= 0;
        else
            curr_clk <= curr_clk + 1;
    end

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            number_of_successful_transfers <= 0;
        end else if (s_ack.valid && s_ack.ready) begin
            number_of_successful_transfers <= number_of_successful_transfers + 1;
        end
    end


    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            phase <= PHASE_STARTUP;
            phase_timer <= 0;;
            background_load <= 5;
            incast_active <= 0;
            send_credits <= 0;
        end else begin
            phase_timer <= phase_timer + 1;

            case (phase)
                PHASE_STARTUP: begin
                    background_load <= 5 + ($urandom % 3); 
                    incast_active <= 0;

                    if (phase_timer >= 10000) begin
                        phase <= PHASE_COMPUTE;
                        phase_timer <= 0;
                        send_credits <= send_credits + 100;
                    end
                end
                PHASE_COMPUTE: begin
                    background_load <= 5 + ($urandom % 3); 
                    incast_active <= 0;

                    if ((phase_timer % 5000) == 0) begin
                        send_credits <= send_credits + 1; //total sent 10
                    end

                    if (phase_timer >= 125000) begin
                        phase <= PHASE_SYNC;
                        phase_timer <= 0;
                    end
                end
                PHASE_SYNC: begin
                    background_load <= 90 + ($urandom % 8); 
                    incast_active <= (($urandom % 1000) < 20);

                    if ((phase_timer % 125) == 0) begin
                        send_credits <= send_credits + 1;
                    end

                    if (phase_timer >= 12500) begin 
                        difference_at_start_of_recovery <= send_credits - packets_sent;
                        phase <= PHASE_RECOVERY;
                        phase_timer <= 0;
                    end
                end
                PHASE_RECOVERY: begin
                    if (send_credits > packets_sent) begin
                        background_load <= 60 + 20*(send_credits - packets_sent)/difference_at_start_of_recovery; 
                    end
                    incast_active <= 0;

                    if (packets_sent >= send_credits) begin
                        phase <= PHASE_COMPUTE;
                        phase_timer <= 0;
                    end
                end
            endcase
        end
    end
        
    initial begin

        aresetn = 0;

        s_req.valid = 0;
        s_ack.valid = 0;

        m_req.ready = 1;
        m_ack.ready = 1;

        packets_sent = 0;
        
        wr_req = '0;

        for (int i = 0; i < 64; i++) begin
            inst_rdma_flow.inst_pntr_table.ram[i] = '0;
        end

        repeat(5) @(posedge aclk);

        aresetn = 1;

        for (int i = 0; i < 100; i++) begin
            wr_req.req_1.opcode = RC_RDMA_WRITE_ONLY;
            wr_req.req_1.pid    = 1;
            wr_req.req_1.vfid   = 0;
            wr_req.req_1.dest   = 0;
            wr_req.req_1.last   = 1;
            wr_req.req_1.len    = bytes_per_packet; 
            wr_req.req_1.vaddr  = 32'h1000 + i*bytes_per_packet;

            send_wr_req(wr_req);
            packets_sent++;
        end

        while (packets_sent < number_of_packets) begin
            if (packets_sent < send_credits) begin
                wr_req.req_1.opcode = RC_RDMA_WRITE_ONLY;
                wr_req.req_1.pid    = 1;
                wr_req.req_1.vfid   = 0;
                wr_req.req_1.dest   = 0;
                wr_req.req_1.last   = 1;
                wr_req.req_1.len    = bytes_per_packet; 
                wr_req.req_1.vaddr  = 32'h1000 + packets_sent*bytes_per_packet;

                send_wr_req(wr_req);
                packets_sent++;
            end
            @(posedge aclk);
        end

    end

    // RTT measurement
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            fifo_count <= 0;
            fifo_tail <= 0;
            fifo_head <= 0;
            rtt <= 0;
        end else begin 
            //write
            if (m_req.valid && m_req.ready && fifo_count < 16) begin
                fifo_time[fifo_tail] <= curr_clk;
                fifo_tail <= (fifo_tail == 15) ? 0 : fifo_tail + 1;
            end
            //read
            if (s_ack.valid && s_ack.ready && fifo_count > 0) begin
                rtt <= curr_clk - fifo_time[fifo_head];
                fifo_head <= (fifo_head == 15) ? 0 : fifo_head + 1;
            end
            //count
            case ({
                (m_req.valid && m_req.ready && (fifo_count < 16)),
                (s_ack.valid && s_ack.ready && (fifo_count > 0))
            })
                2'b10: fifo_count <= fifo_count + 1; // write only
                2'b01: fifo_count <= fifo_count - 1; // read only
                default: ;                           // no change
            endcase
        end
    end



    task send_wr_req(input dreq_t req);
        
        begin
        
            @(posedge aclk);
        
            s_req.data  <= req;
            s_req.valid <= 1'b1;
        
            // wait until DUT accepts it
            while (!s_req.ready)
                @(posedge aclk);
        
        
            s_req.valid <= 1'b0;

        end
    endtask


        // DUT instance
    dbg_rdma_flow inst_rdma_flow (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_req(s_req),
        .m_req(m_req),
        .s_ack(s_ack),
        .m_ack(m_ack),
        //MT zaaron

        .curr_clk(curr_clk),
        .rtt(rtt),
        .dbg_target_delay(dbg_target_delay),
        .dbg_cwnd(dbg_cwnd),
        .dbg_packets_in_flight(dbg_packets_in_flight),
        .dbg_delay(dbg_delay),
        .dbg_m_req_ready(dbg_m_req_ready),
        .dbg_queue_out_valid(dbg_queue_out_valid),
        .dbg_can_send(dbg_can_send),
        .fire_dbg(fire_dbg),
        .dbg_base_rtt(dbg_base_rtt)
    );

    dbg_network_model inst_network_model (
        .aclk(aclk),
        .aresetn(aresetn),
        .m_req(m_req),
        .s_ack(s_ack),
        .curr_clk(curr_clk),
        .load(background_load),
        .incast_active(incast_active)
    );

endmodule