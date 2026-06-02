package lynx_min_pkg;

parameter integer OPCODE_BITS = 5;
parameter integer STRM_BITS = 2;
parameter integer DEST_BITS = 4;
parameter integer PID_BITS = 6;
parameter integer VADDR_BITS = 48;
parameter integer LEN_BITS = 28;
parameter integer OFFS_BITS = 6;

parameter integer RDMA_N_WR_OUTSTANDING = 16;
parameter integer AXI_DATA_BITS = 512;


//opcode stuff
parameter integer RC_SEND_FIRST = 5'h0;
parameter integer RC_SEND_MIDDLE = 5'h1;
parameter integer RC_SEND_LAST = 5'h2;
parameter integer RC_SEND_ONLY = 5'h4;
parameter integer RC_RDMA_WRITE_FIRST = 5'h6;
parameter integer RC_RDMA_WRITE_MIDDLE = 5'h7;
parameter integer RC_RDMA_WRITE_LAST = 5'h8;
parameter integer RC_RDMA_WRITE_LAST_WITH_IMD = 5'h9;
parameter integer RC_RDMA_WRITE_ONLY = 5'hA;
parameter integer RC_RDMA_WRITE_ONLY_WIT_IMD = 5'hB;
parameter integer RC_RDMA_READ_REQUEST = 5'hC;
parameter integer RC_RDMA_READ_RESP_FIRST = 5'hD;
parameter integer RC_RDMA_READ_RESP_MIDDLE = 5'hE;
parameter integer RC_RDMA_READ_RESP_LAST = 5'hF;
parameter integer RC_RDMA_READ_RESP_ONLY = 5'h10;
parameter integer RC_ACK = 5'h11;

typedef struct packed {
        logic [OPCODE_BITS-1:0] opcode; // One of the values of coyote::CoyoteOper
        logic [STRM_BITS-1:0] strm;     // One of STRM_CARD, STRM_HOST, STRM_TCP, or STRM_RDMA (this determines the where this request lands)
        logic remote;
        logic host;                     // Whether the corresponding request came from the corresponding vFPGA sq_* interface or a host-side invoke
        logic [DEST_BITS-1:0] dest;     // The index of the AXI stream that data arrives at/departs from
        logic [PID_BITS-1:0] pid;
        logic [DEST_BITS-1:0] vfid;
        logic [7:0]              rsrvd;   // simplified
    } ack_t;

    typedef struct packed {
        // Opcode
        logic [OPCODE_BITS-1:0] opcode; // One of the values of coyote::CoyoteOper
        logic [STRM_BITS-1:0] strm;     // One of STRM_CARD, STRM_HOST, STRM_TCP, or STRM_RDMA (this determines the where this request lands)
        logic mode;                     // In the STRM_RDMA case, controls whether to skip the request splitter in the dreq_rdma_parser_wr module
        logic rdma;
        logic remote;

        // ID
        logic [DEST_BITS-1:0] vfid; // rsrvd
        logic [PID_BITS-1:0] pid;
        logic [DEST_BITS-1:0] dest; // The index of the AXI stream that data arrives at/departs from

        // FLAGS
        logic last; // Only if last is high, the corresponding AXI stream will have a last signal at the end. Otherwise, the stream will end without a last signal, the checkCompleted counter will not be incremented and no acknowledgement will be sent on the corresponding cq_* interface

        // DESC
        logic [VADDR_BITS-1:0] vaddr;
        logic [LEN_BITS-1:0] len;

        // RSRVD
        logic actv; // rsrvd
        logic host; // rsrvd
        logic [OFFS_BITS-1:0] offs; // rsrvd

        logic [7:0] rsrvd;
    } req_t;


    typedef struct packed {
        req_t req_1; // rd, local
        req_t req_2; // wr, remote
    } dreq_t;

    typedef struct packed {
        ack_t ack;
        logic last;
    } dack_t;
    
    function logic is_opcode_rd_resp;
    input [OPCODE_BITS-1:0] opcode;
    begin
        if (opcode == RC_RDMA_READ_RESP_FIRST ||
            opcode == RC_RDMA_READ_RESP_MIDDLE ||
            opcode == RC_RDMA_READ_RESP_LAST ||
            opcode == RC_RDMA_READ_RESP_ONLY) begin
            is_opcode_rd_resp = 1'b1;
        end
        else begin
            is_opcode_rd_resp = 1'b0;
        end
    end
    endfunction


    function logic is_opcode_rd_req;
    input [OPCODE_BITS-1:0] opcode;
    begin
        if (opcode == RC_RDMA_READ_REQUEST) begin
            is_opcode_rd_req = 1'b1;
        end
        else begin
            is_opcode_rd_req = 1'b0;
        end
    end
    endfunction

    //stuff for testbench
    typedef enum logic [1:0] {
        PHASE_STARTUP,
        PHASE_COMPUTE,
        PHASE_SYNC,
        PHASE_RECOVERY
    } phase_t;

endpackage