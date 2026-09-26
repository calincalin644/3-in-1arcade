`timescale 1ns/1ps
module render;
    reg clk=0, rst_n=0;
    always #20 clk=~clk;
    wire [7:0] out;
    tt_um_breakout dut(.clk(clk),.rst_n(rst_n),.ena(1'b1),.ui_in(8'b0),
        .uio_in(8'b0),.uo_out(),.uio_out(out),.uio_oe());
    integer fd,h,v;
    reg [7:0] red,green,blue;
    initial begin
        fd=$fopen("build/preview.ppm","wb");
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
        $display("Rendered build/preview.ppm from actual VGA output pins");
        $finish;
    end
endmodule
