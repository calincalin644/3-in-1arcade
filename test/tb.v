`default_nettype none
`timescale 1ns/1ps
module tb;
    reg clk=0;
    always #20 clk=~clk; // 25 MHz simulation; cycle counts match 25.2 MHz hardware.
    reg rst_n=0, ena=1;
    reg [7:0] ui_in=0, uio_in=0;
    wire [7:0] uo_out, uio_out, uio_oe;
`ifdef GL_TEST
    wire VPWR=1'b1, VGND=1'b0;
`endif
    tt_um_breakout user_project (
`ifdef GL_TEST
        .VPWR(VPWR), .VGND(VGND),
`endif
        .clk(clk), .rst_n(rst_n), .ena(ena), .ui_in(ui_in), .uio_in(uio_in),
        .uo_out(uo_out), .uio_out(uio_out), .uio_oe(uio_oe)
    );
    // Optional frame capture; tests do not dump huge internal waveform traces.
endmodule
`default_nettype wire
