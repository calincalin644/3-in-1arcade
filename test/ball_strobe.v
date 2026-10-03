// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps
module ball_strobe;
    reg [8:0] x=160;
    reg [7:0] y=160;
    reg pong=0, phase=0;
    reg [1:0] state=0;
    wire [5:0] rgb;
    integer m,s,p;
    breakout_renderer renderer(x,y,1'b1,pong,8'd112,8'd96,8'd128,8'd160,
                               16'b0,2'd3,state,rgb,phase);
    initial begin
        for(m=0;m<2;m=m+1)
        for(s=0;s<4;s=s+1)
        for(p=0;p<2;p=p+1) begin
            pong=m;state=s;phase=p;x=160;y=160;#1;
            if((rgb==6'b111111)!==(s==0 || (s==1 && p==1)))
                $fatal(1,"Ball visibility mode=%0d state=%0d phase=%0d",m,s,p);
            x=150;y=220;#1;
            if(rgb!==6'b001111) $fatal(1,"Strobe changed paddle");
            x=32;y=12;#1;
            if(rgb!==6'b111111) $fatal(1,"Strobe changed lives");
        end
        $display("PASS: stationary serve ball, alternating PLAY visibility, paddles/lives unchanged");
        $finish;
    end
endmodule
