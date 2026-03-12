`timescale 1ns/1ps

module dbg_rdma_congestion_control_tb;

    logic [31:0] rtt;
    logic ack_event;
    logic aclk;
    logic aresetn;
    logic dummy_out;

    int ack_count;

    // Clock: 100 MHz
    initial aclk = 0;
    always #5 aclk = ~aclk;

    // DUT instance
    dbg_rdma_congestion_control dut (
        .rtt(rtt),
        .ack_event(ack_event),
        .aclk(aclk),
        .aresetn(aresetn),
        .dummy_out(dummy_out)
    );

    // Network simulation parameters
    parameter RTT_CYCLES = 100;

    int send_times [0:999];
    int send_ptr = 0;
    int recv_ptr = 0;
    int cycle_counter = 0;

    initial begin
        rtt = 0;
        ack_event = 0;
        aresetn = 0;
        ack_count = 0;

        // Reset
        repeat (5) @(posedge aclk);
        aresetn = 1;

        forever @(posedge aclk) begin

            // global cycle counter
            cycle_counter++;

            // Packet sent by DUT
            if (dummy_out) begin
                send_times[send_ptr] = cycle_counter + RTT_CYCLES;
                send_ptr++;
            end

            // ACK arrives
            if (recv_ptr < send_ptr &&
                cycle_counter >= send_times[recv_ptr]) begin

                rtt <= RTT_CYCLES;
                ack_event <= 1;

                recv_ptr++;
                ack_count++;

            end else begin
                ack_event <= 0;
            end
        end
    end

endmodule