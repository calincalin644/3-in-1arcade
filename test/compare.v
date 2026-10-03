// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps
module equivalence_case #(parameter MODE=0)(
    input wire clk,rst,ena,frame,left,right,up,down,launch,check,
    input wire [31:0] frame_number
);
    wire [5:0] x,y,a,b;
    wire [7:0] rx,ry,ra,rb,rscore;
    wire [15:0] bricks,rbricks;
    wire [1:0] lives,state,rlives,rstate;
    wire [2:0] direction,rdirection;
    wire lost,won,done,launch_saved,rlost,rwon,restart;
    arcade_engine dut(clk,rst,ena,frame,left,right,up,down,launch,
        MODE==1,MODE==2,state,x,y,a,b,bricks,direction,lost,won,done,launch_saved,);
    arcade_session session(clk,rst,ena,done,launch_saved,lost,won,lives,state,);
    reference_session ref_session(clk,rst,ena,frame,launch,rlost,rwon,rlives,rstate,restart);
    generate if(MODE==2) begin: maze
        reference_pacman_game reference_game(clk,rst,ena,frame,left,right,up,down,launch,rstate,restart,
            rx,ry,ra,rb,rdirection,rscore,rlost,rbricks,rwon);
        always @(posedge check) begin
            if({direction,dut.ghost_dir,bricks} !==
               {rdirection,reference_game.ghost_dir,rbricks})
                $fatal(1,"Maze steering/pellets differ at frame %0d",frame_number);
        end
    end else begin: paddle
        reference_paddle_game #(.COARSE_CPU(MODE==1)) reference_game(clk,rst,ena,frame,left,right,MODE==1,rstate,restart,
            ra,rb,rx,ry,rbricks[15:0],rlost,rwon);
        always @(posedge check) begin
            if({direction[1:0],bricks} !==
               {reference_game.dy_down,reference_game.dx_right,rbricks})
                $fatal(1,"Paddle direction/bricks differ mode=%0d frame=%0d",MODE,frame_number);
        end
    end endgenerate
    always @(posedge check) begin
        if({x,2'b0,y,2'b0,a,2'b0,b,2'b0,lives,state} !== {rx,ry,ra,rb,rlives,rstate})
            $fatal(1,"Mode %0d frame %0d: actual grid %h/%h/%h/%h lives/state %d/%d reference pixels %h/%h/%h/%h %d/%d",
                MODE,frame_number,x,y,a,b,lives,state,rx,ry,ra,rb,rlives,rstate);
        if(dut.phase!==0) $fatal(1,"Engine did not finish within blanking budget");
    end
endmodule

module compare;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=0,ena=1,frame=0,left=0,right=0,up=0,down=0,launch=0,check=0;
    reg [31:0] rng=32'h12345678,frame_number=0;
    equivalence_case #(0) breakout(clk,rst,ena,frame,left,right,up,down,launch,check,frame_number);
    equivalence_case #(1) pong(clk,rst,ena,frame,left,right,up,down,launch,check,frame_number);
    equivalence_case #(2) pacman(clk,rst,ena,frame,left,right,up,down,launch,check,frame_number);
    initial begin
        repeat(4) @(negedge clk); rst=1;
        for(frame_number=0;frame_number<10000;frame_number=frame_number+1) begin
            @(negedge clk);
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            if(frame_number%16==0) begin
                left=rng[0];right=rng[1];up=rng[2];down=rng[3];
            end
            launch=frame_number%61==0; ena=frame_number%29!=0;
            repeat(4) @(negedge clk);
            frame=1;
            @(negedge clk); frame=0;
            repeat(32) @(negedge clk);
            check=1; #1; check=0;
        end
        $display("PASS: coarse engines match scaled reference gameplay for 10000 frames each");
        $finish;
    end
    initial begin #100000000; $fatal(1,"Equivalence test timeout"); end
endmodule
