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

    metaIntf.s                  s_req,
    metaIntf.m                  m_req
);





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

    .s_req(s_req),
    .m_req(m_req)
);

endmodule