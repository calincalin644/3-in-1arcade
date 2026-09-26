`default_nettype none
module top(input wire clk, rst_n, input wire [7:0] ui_in,
           output wire [7:0] uo_out, inout wire [7:0] uio);
    wire [7:0] uio_in, uio_out, uio_oe;
    SB_IO #(.PIN_TYPE(6'b101001)) uio_pin[7:0] (
        .PACKAGE_PIN(uio), .OUTPUT_ENABLE(uio_oe),
        .D_OUT_0(uio_out), .D_IN_0(uio_in));
    tt_um_breakout game(.clk(clk), .rst_n(rst_n), .ena(1'b1), .ui_in(ui_in),
        .uo_out(uo_out), .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe));
endmodule
`default_nettype wire
