`timescale 1ns/1ps

module dbg_rdma_congestion_control_tb;

    logic [31:0] rtt;
    logic ack_event;
    logic aclk;
    logic aresetn;
    logic dummy_out;

    // Clock: 100 MHz (10ns period)
    initial aclk = 0;
    always #5 aclk = ~aclk;

    // DUT
    dbg_rdma_congestion_control dut (
        .rtt(rtt),
        .ack_event(ack_event),
        .aclk(aclk),
        .aresetn(aresetn),
        .dummy_out(dummy_out)
    );

    initial begin
        // Initialize
        rtt = 0;
        ack_event = 0;
        aresetn = 0;

        // Reset for 20ns
        #20;
        aresetn = 1;

        // ---- Test 1: Low RTT (should increase cwnd) ----
        repeat (20) begin
            #10;
            rtt = 32'd100;
            ack_event = 1;
            #10;
            ack_event = 0;
        end

        // ---- Test 2: Higher RTT (should decrease cwnd) ----
        repeat (20) begin
            #10;
            rtt = 32'd200;
            ack_event = 1;
            #10;
            ack_event = 0;
        end

        #200;

        $stop;
    end

endmodule