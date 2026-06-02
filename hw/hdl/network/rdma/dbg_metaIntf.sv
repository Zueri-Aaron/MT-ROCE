interface dbg_metaIntf #(type STYPE = logic);

    logic valid;
    logic ready;
    STYPE data;

    modport s (
        output valid,
        output data,
        input  ready
    );

    modport m (
        input  valid,
        input  data,
        output ready
    );

endinterface