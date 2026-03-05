import lynxTypes::*;

module dbg_rtt_changer (
    input  logic                aclk,
    input  logic                aresetn,

    input  logic [31:0]         rtt,
    input  logic                ack_event,

    metaIntf.s                  s_req,
    metaIntf.m                  m_req
);





rdma_congestion_control inst_swift(
    .aclk(aclk),
    .aresetn(aresetn),

    .rtt(rtt),
    .ack_event(ack_event),

    .s_req(s_req),
    .m_req(m_req)
);

endmodule