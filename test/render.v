`timescale 1ns/1ps
module render;
    reg clk=0, rst_n=0;
    always #20 clk=~clk;
    wire [7:0] out;
    reg [7:0] ui=0;
    integer mode;
    reg [1023:0] output_path;
    tt_um_breakout dut(.clk(clk),.rst_n(rst_n),.ena(1'b1),.ui_in(ui),
        .uio_in(8'b0),.uo_out(),.uio_out(out),.uio_oe());
    integer fd,h,v;
    reg [7:0] red,green,blue;
    initial begin
        // +MODE=0/1/2 selects Breakout/Pong/Pacman through the real reset inputs.
        if (!$value$plusargs("MODE=%d",mode)) mode=0;
        case(mode)
            0: ui=8'h00;
            1: ui=8'h08;
            2: ui=8'h88;
            default: $fatal(1,"MODE must be 0, 1 or 2");
        endcase
        if (!$value$plusargs("OUTPUT=%s",output_path)) output_path="build/preview.ppm";
        fd=$fopen(output_path,"wb");
        if (!fd) $fatal(1,"Cannot open output image");
        $fwrite(fd,"P6\n640 480\n255\n");
        repeat(3) @(negedge clk);
        rst_n=1;
        for(v=0;v<480;v=v+1) begin
            for(h=0;h<800;h=h+1) begin
                @(posedge clk); #1;
                if(h<640) begin
                    red={out[0],out[4]}*85;
                    green={out[1],out[5]}*85;
                    blue={out[2],out[6]}*85;
                    $fwrite(fd,"%c%c%c",red,green,blue);
                end
            end
        end
        $fclose(fd);
        $display("Rendered mode %0d to %0s from actual VGA output pins",mode,output_path);
        $finish;
    end
endmodule
