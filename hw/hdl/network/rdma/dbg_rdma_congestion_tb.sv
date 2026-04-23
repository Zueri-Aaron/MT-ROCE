`timescale 1ns/1ps

module dbg_rdma_congestion_control_tb;


    logic [31:0] rtt;
    logic ack_event;
    logic aclk;
    logic aresetn;
    logic dummy_out;

    int packet_count;
    int ack_count;
    int packets_in_buffer;

    // Clock: 100 MHz
    initial aclk = 0;
    always #5 aclk = ~aclk;

    // DUT instance
    dbg_rdma_congestion_control dut (
        .rtt(rtt),
        .ack_event(ack_event),
        .curr_clk(curr_clk),
        .aclk(aclk),
        .aresetn(aresetn),
        .dummy_out(dummy_out)
    );

    // Network simulation parameters
    parameter RTT1 = 1100;
    parameter RTT2 = 1230;
    parameter SWITCH1 = 55;

    int send_times [0:999];
    int send_ptr = 0;
    int recv_ptr = 0;
    int cycle_counter = 0;
    int current_rtt;
    logic[31:0] curr_clk;
    
    initial begin
        rtt = 0;
        ack_event = 0;
        aresetn = 0;
        packet_count = 0;
        current_rtt = 0;
        ack_count = 0;
        packets_in_buffer = 0;

        // Reset
        repeat (5) @(posedge aclk);
        aresetn = 1;

        forever @(posedge aclk) begin

            // global cycle counter
            cycle_counter++;

            // Packet sent by DUT
            if (dummy_out && packets_in_buffer < 1001) begin
                if (packet_count < SWITCH1) begin
                    current_rtt = RTT1;
                end else begin 
                    current_rtt = RTT2;
                end
                packet_count++;
                send_times[send_ptr] = cycle_counter + current_rtt;
                send_ptr = (send_ptr + 1) % 1000;
                packets_in_buffer++;
            end

            // ACK arrives
            if (packets_in_buffer > 0 &&
                cycle_counter >= send_times[recv_ptr]) begin

                if (ack_count < SWITCH1) begin
                    rtt = RTT1;
                end else begin 
                    rtt = RTT2;
                end
                
                ack_event = 1;
                curr_clk = cycle_counter;

                recv_ptr = (recv_ptr + 1) % 1000;
                ack_count++;
                packets_in_buffer--;

            end else begin
                ack_event = 0;
            end
        end
    end

endmodule