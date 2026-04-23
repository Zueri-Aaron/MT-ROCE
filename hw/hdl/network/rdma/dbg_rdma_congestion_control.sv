module dbg_rdma_congestion_control (
    input  logic [31:0]         rtt,
    input  logic                ack_event,
    input  logic [31:0]         curr_clk,

    input  logic                aclk,
    input  logic                aresetn,

    output logic                dummy_out
);

localparam logic[4:0] MAX_CWND = 32;

localparam logic[9:0] target_delay_LUT[0:15] = {256, 156, 112, 85, 67, 54, 44, 35, 28, 23, 18, 13, 9, 6, 3, 1};
localparam logic[3:0] precision = 10;
localparam logic[9:0] decrease_factor_LUT[0:15] = {10'd1, 10'd2, 10'd2, 10'd3, 10'd4, 10'd5, 10'd6, 10'd7, 10'd9, 10'd11, 10'd15, 10'd19, 10'd27, 10'd43, 10'd91, 10'd256}; // = beta/target_delay

localparam logic[4:0] MAX_CWND = 32;

localparam logic[9:0] target_delay_LUT[0:15] = {256, 156, 112, 85, 67, 54, 44, 35, 28, 23, 18, 13, 9, 6, 3, 1};
localparam logic[3:0] precision = 10;
localparam logic[9:0] decrease_factor_LUT[0:15] = {10'd1, 10'd2, 10'd2, 10'd3, 10'd4, 10'd5, 10'd6, 10'd7, 10'd9, 10'd11, 10'd15, 10'd19, 10'd27, 10'd43, 10'd91, 10'd256}; // = beta/target_delay

localparam integer cwnd_values[0:15] = {10, 14, 18, 25, 34, 46, 63, 86, 117, 158, 215, 293, 398, 541, 736, 1000}; //in log2 accuracy LUT
localparam logic[8:0] target_delay_LUT[0:15] = {9'd300, 9'd249, 9'd216, 9'd178, 9'd148, 9'd122, 9'd100, 9'd80, 9'd64, 9'd51, 9'd39, 9'd28, 9'd20, 9'd12, 9'd6, 9'd1}; // log2 accuracy LUT
localparam logic[11:0] slope_target_delay_LUT[0:14] = {12'd3264, 12'd2112, 12'd1390, 12'd853, 12'd555, 12'd331, 12'd223, 12'd132, 12'd81, 12'd54, 12'd36, 12'd20, 12'd14, 12'd8, 12'd6}; // log2 accuracy LUT
integer i;

localparam integer decrease_factor_LUT[0:14] = {7, 8, 9, 12, 14, 17, 20, 26, 32, 41, 53, 73, 102, 171, 341}; // = 1/target_delay

localparam MIN_DELAY = 16;

integer seg_idx;
logic [31:0] base_rtt;
logic [31:0] target_delay;
logic [9:0] target_delay_factor;
logic [31:0] acc; // accumulated ACKs for avoiding division
logic [31:0] acc_next;
logic [31:0] cwnd; // congestion window in number of packets
logic [31:0] cwnd_next;
logic [31:0] packets_in_flight; // number of packets currently in flight
logic [31:0] packets_in_flight_next;
logic [31:0] delay; 
logic [3:0] target_index;

logic [31:0] delta;
logic [41:0] mult1;
logic [46:0] mult2;
logic [31:0] decrease;

logic [31:0] last_decrease;

always_comb begin
    target_index = (cwnd > 15) ? 4'd15 : cwnd[3:0] - 1;
    target_delay_factor = target_delay_LUT[target_index];
    target_delay = (target_delay_factor * base_rtt) >> precision;
    
    delay = (rtt > base_rtt) ? (rtt - base_rtt) : 32'd0;
end

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        base_rtt <= 32'hFFFF_FFFF; // max value
        cwnd <= 32'd1;
        acc <= 32'd0;
        packets_in_flight <= 32'd0;
        dummy_out <= 1'b0;
        last_decrease <= 0;
    end else begin 
        packets_in_flight_next = packets_in_flight;
        cwnd_next = cwnd;
        acc_next = acc;

        if (ack_event) begin
            packets_in_flight_next = (packets_in_flight_next > 0) ? packets_in_flight_next - 1 : 0;
            if (rtt < base_rtt)
                base_rtt <= rtt;    

            if (delay <= target_delay) begin
                acc_next = acc + 1;     // additive constant alpha_i = 1
                if (acc_next >= cwnd) begin
                    acc_next = acc_next - cwnd;
                    if (cwnd != MAX_CWND)
                        cwnd_next = cwnd + 1;
                end 
            end else if (rtt < (curr_clk - last_decrease)) begin  
                delta = delay - target_delay;
                mult1 = delta * decrease_factor_LUT[target_index];
                mult2 = mult1 * cwnd[4:0];
                decrease = mult2 >> precision;

                if (decrease > (cwnd >> 1)) // rn max multiplicative decrease is 1/2
                    cwnd_next = cwnd - (cwnd >> 1);
                else 
                    cwnd_next = cwnd - decrease;

                if (cwnd_next < 1)
                if (cwnd_next < 1)
                    cwnd_next = 1;
                
                if (cwnd_next < cwnd)
                    last_decrease <= curr_clk;

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