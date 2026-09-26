`timescale 1ns/1ps
module unit;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, frame=0, ena=1;
    reg [7:0] ui=0;
    wire left, right, launch, up, down;
    breakout_controls controls(clk,rst_n,frame,ui,left,right,launch,up,down);
    reg gl=0, gr=0, gf=0;
    wire [7:0] paddle,bx,by;
    wire [31:0] bricks;
    wire [1:0] lives,state;
    wire game_lost, game_won, game_restart;
    wire [7:0] unused_cpu;
    arcade_session game_session(clk,rst_n,ena,frame,gf,game_lost,game_won,lives,state,game_restart);
    paddle_game game(clk,rst_n,ena,frame,gl,gr,1'b0,state,game_restart,
                     paddle,unused_cpu,bx,by,bricks,game_lost,game_won);
    reg pl=0, pr=0, pf=0;
    wire [7:0] pp, cp, pbx, pby;
    wire [1:0] plives, pstate;
    wire pong_lost, pong_won, pong_restart;
    wire [31:0] unused_bricks;
    arcade_session pong_session(clk,rst_n,ena,frame,pf,pong_lost,pong_won,plives,pstate,pong_restart);
    paddle_game pong(clk,rst_n,ena,frame,pl,pr,1'b1,pstate,pong_restart,
                     pp,cp,pbx,pby,unused_bricks,pong_lost,pong_won);
    reg pal=0, par=0, pau=0, pad=0, paf=0;
    wire [7:0] pacx, pacy, ghostx, ghosty, pacscore;
    wire [1:0] paclives, pacstate;
    wire [2:0] pacdir;
    wire pacmouth;
    wire pac_lost, pac_restart;
    arcade_session pac_session(clk,rst_n,ena,frame,paf,pac_lost,1'b0,paclives,pacstate,pac_restart);
    pacman_game pac(clk,rst_n,ena,frame,pal,par,pau,pad,paf,pacstate,pac_restart,
                    pacx,pacy,ghostx,ghosty,pacdir,pacmouth,pacscore,pac_lost);
    reg [7:0] top_ui=0;
    wire [7:0] top_uo, top_uio, top_oe;
    tt_um_breakout top_dut(
        .ui_in(top_ui), .uo_out(top_uo), .uio_in(8'b0),
        .uio_out(top_uio), .uio_oe(top_oe),
        .ena(ena), .clk(clk), .rst_n(rst_n));
    task clocks(input integer n);
        repeat(n) begin @(posedge clk); #1; end
    endtask
    task tick;
        begin @(negedge clk); frame=1; clocks(1); @(negedge clk); frame=0; clocks(1); end
    endtask
    task top_tick;
        begin
            @(negedge clk); force top_dut.frame=1'b1; clocks(1);
            @(negedge clk); release top_dut.frame; clocks(2);
        end
    endtask
    task reset;
        begin @(negedge clk); rst_n=0; clocks(3); @(negedge clk); rst_n=1; clocks(3); end
    endtask
    task packet(input [23:0] data);
        integer i;
        begin
            for(i=23;i>=0;i=i-1) begin
                @(negedge clk); ui[6]=data[i]; ui[5]=0; clocks(8);
                @(negedge clk); ui[5]=1; clocks(8);
                @(negedge clk); ui[5]=0; clocks(8);
            end
            @(negedge clk); ui[4]=1; clocks(8);
            @(negedge clk); ui[4]=0; clocks(8);
        end
    endtask
    integer i, mode, mx, my;
    reg [7:0] expected_digit;
    reg [15:0] maze_row;
    initial begin
        reset;
        if(paddle!==112 || bx!==128 || state!==0 || lives!==3 || bricks!==32'hffffffff)
            $fatal(1,"Reset state");
        // Bounce rejection and per-button qualification at two frame samples.
        ui[0]=1; clocks(4); tick;
        if(left) $fatal(1,"DIP accepted after only one sample");
        ui[0]=0; clocks(4); tick;
        if(left) $fatal(1,"DIP bounce accepted");
        ui[0]=1; clocks(4); tick; tick;
        if(!left) $fatal(1,"DIP left missing");
        ui[1]=1; clocks(4); tick; tick;
        if(!left || !right) $fatal(1,"Both direction inputs");
        ui[2]=1; clocks(4); tick; tick;
        if(!launch) $fatal(1,"Launch edge missing");
        tick;
        if(launch) $fatal(1,"Held launch repeats");
        ui[2:0]=0; clocks(4); tick; tick; tick;
        // Controller 2 must not affect controller 1. 0x020=left, 0x010=right.
        packet(24'h020000);
        if(left || right || launch) $fatal(1,"Wrong controller order");
        packet(24'h000020);
        if(!left || right) $fatal(1,"Pad left decode");
        packet(24'h000010);
        if(left || !right) $fatal(1,"Pad right decode");
        packet(24'h000080);
        if(!up || down) $fatal(1,"Pad up decode");
        packet(24'h000040);
        if(up || !down) $fatal(1,"Pad down decode");
        packet(24'h000008);
        if(!launch) $fatal(1,"Pad A decode");
        tick;
        if(launch) $fatal(1,"Pad A repeats");
        packet(24'hffffff);
        if(left || right || launch) $fatal(1,"Disconnected pad not released");
        tick;
        packet(24'h000100);
        if(!launch) $fatal(1,"Start decode");
        tick;
        packet(24'h000020);
        repeat(122) tick;
        if(left) $fatal(1,"Stale controller held left");

        // Game movement, clamps, opposed inputs, launch.
        reset; gl=1;
        repeat(50) tick;
        if(paddle!==0) $fatal(1,"Left clamp");
        gr=1; tick;
        if(paddle!==0) $fatal(1,"Opposed movement");
        gl=0; repeat(90) tick;
        if(paddle!==224) $fatal(1,"Right clamp");
        gr=0; gf=1; tick; gf=0;
        if(state!==1) $fatal(1,"Launch does not start");
        ena=0; tick;
        if(by!==217) $fatal(1,"ena hold");
        ena=1;
        // Directed collision scenarios use only this RTL unit test.
        @(negedge clk); game.ball_x=253; game.ball_y=150; game.dx_right=1; game.dy_down=0;
        tick;
        if(game.dx_right!==0 || bx!==253) $fatal(1,"Right wall bounce");
        @(negedge clk); game.ball_x=2; game.dx_right=0;
        tick;
        if(game.dx_right!==1 || bx!==2) $fatal(1,"Left wall bounce");
        @(negedge clk); game.ball_y=26; game.dy_down=0;
        tick;
        if(game.dy_down!==1 || by!==26) $fatal(1,"Ceiling bounce");
        @(negedge clk); game.ball_x=128; game.ball_y=66; game.dy_down=0; game.dx_right=1;
        tick;
        if(bricks[28]!==0 || game.dy_down!==1 || by!==66) $fatal(1,"Brick hit");
        @(negedge clk); game.paddle=112; game.ball_x=120; game.ball_y=217; game.dy_down=1;
        tick;
        if(game.dy_down!==0 || by!==217 || game.dx_right!==0) $fatal(1,"Paddle left bounce");
        @(negedge clk); game.ball_x=135; game.ball_y=217; game.dy_down=1;
        tick;
        if(game.dy_down!==0 || game.dx_right!==1) $fatal(1,"Paddle right bounce");
        // Missing paddle costs one life and holds for a new launch edge.
        for(i=2;i>=0;i=i-1) begin
            @(negedge clk); game.ball_y=235; game_session.state=1;
            tick;
            if(lives!==i || state!==((i==0)?2:0)) $fatal(1,"Life/game-over transition");
        end
        gf=1; tick; gf=0;
        if(state!==0 || lives!==3 || bricks!==32'hffffffff) $fatal(1,"Restart");
        @(negedge clk); game_session.state=1; game.bricks=0;
        tick;
        if(state!==3) $fatal(1,"Win transition");
        gf=1; tick; gf=0;
        if(state!==0 || lives!==3 || bricks!==32'hffffffff) $fatal(1,"Win restart");

        // Pong shares the frame-rate update and input contract.
        reset; pl=1; repeat(10) tick;
        if(pp >= 112) $fatal(1,"Pong left movement");
        pl=0; pr=1; repeat(20) tick;
        if(pp <= 112) $fatal(1,"Pong right movement");
        pr=0; pf=1; tick; pf=0;
        if(pstate!==1) $fatal(1,"Pong launch");
        @(negedge clk); pong.ball_x=120; pong.ball_y=217; pong.paddle=112;
        pong.dy_down=1; tick;
        if(pong.dy_down!==0 || pby!==216) $fatal(1,"Pong player bounce");
        @(negedge clk); pong.ball_x=128; pong.ball_y=26; pong.cpu_paddle=112;
        pong.dy_down=0; tick;
        if(pong.dy_down!==1 || pby!==26) $fatal(1,"Pong CPU bounce");

        // The third mode is a frame-based Pacman maze game.
        for(my=0;my<16;my=my+1) begin
            case(my)
                0: maze_row=16'hffff; 1: maze_row=16'h8001; 2: maze_row=16'h8ff1;
                3: maze_row=16'h8101; 4: maze_row=16'h8171; 5: maze_row=16'h8001;
                6: maze_row=16'h8e71; 7: maze_row=16'h8001; 8: maze_row=16'h8171;
                9: maze_row=16'h8101; 10: maze_row=16'h8ff1; default: maze_row=16'hffff;
            endcase
            for(mx=0;mx<16;mx=mx+1)
                if(pac.maze_wall(mx[3:0],my[3:0])!==maze_row[mx])
                    $fatal(1,"Maze collision map differs at %0d,%0d",mx,my);
        end
        reset; paf=1; tick; paf=0;
        if(pacstate!==1) $fatal(1,"Pacman launch");
        par=1; repeat(10) tick; par=0;
        if(pacx <= 16) $fatal(1,"Pacman right movement");
        // The red ghost approaches a wall at (11,10) and must turn into the
        // open corridor above it rather than entering the blocked tile.
        @(negedge clk); pac.ghost_x=12*16; pac.ghost_y=10*16;
        pac.pac_x=16; pac.pac_y=16; pac.ghost_dir=1;
        tick;
        if(pac.ghost_x[7:4]!==12 || pac.ghost_y[7:4]!==9)
            $fatal(1,"Pacman ghost did not turn around wall");
        @(negedge clk); pac.pac_x=16; pac.pac_y=16;
        pac.ghost_x=16; pac.ghost_y=16; pac_session.state=1;
        tick;
        if(paclives!==2 || pacstate!==0) $fatal(1,"Pacman collision/life");
        top_ui=8'h88; reset;
        if({top_dut.pacman_mode,top_dut.pong_mode}!==2'b10) $fatal(1,"Pacman selector");
        top_ui=8'h08; reset;
        if({top_dut.pacman_mode,top_dut.pong_mode}!==2'b01) $fatal(1,"Pong selector");
        // The common life counter must drive the display in every mode,
        // including the reserved-mode fallback.
        for(mode=0;mode<4;mode=mode+1) begin
            top_ui = ((mode & 2) << 6) | ((mode & 1) << 3);
            reset;
            if(top_uo!==8'h4f || top_oe!==8'hff)
                $fatal(1,"Display reset or VGA output enables");
            for(i=0;i<4;i=i+1) begin
                @(negedge clk);
                top_dut.session.lives=i;
                clocks(1);
                case(i)
                    0: expected_digit=8'h3f;
                    1: expected_digit=8'h06;
                    2: expected_digit=8'h5b;
                    3: expected_digit=8'h4f;
                endcase
                if(top_uo!==expected_digit)
                    $fatal(1,"Wrong lives digit: mode=%0d lives=%0d out=%h", mode,i,top_uo);
            end
            force top_dut.launch=1'b1; top_tick; release top_dut.launch;
            if(top_dut.state!==1) $fatal(1,"Selected game did not launch");
            // An inactive engine's collision must neither cost a life nor
            // move that engine. Modes cannot change without a reset.
            top_ui=~top_ui;
            @(negedge clk);
            if(mode==3) top_dut.game.ball_y=240;
            else begin
                top_dut.pacman.ghost_x=16;
                top_dut.pacman.ghost_y=16;
            end
            top_tick;
            if(top_dut.lives!==3 || top_dut.state!==1)
                $fatal(1,"Inactive game changed shared session");
            if(mode==3 && top_dut.game.ball_y!==240)
                $fatal(1,"Inactive paddle engine moved");
            if(mode!=3 && top_dut.pacman.pac_x!==16)
                $fatal(1,"Inactive maze engine moved");
            for(i=2;i>=0;i=i-1) begin
                @(negedge clk); top_dut.session.state=1;
                if(mode==3) begin
                    top_dut.pacman.pac_x=16; top_dut.pacman.pac_y=16;
                    top_dut.pacman.ghost_x=16; top_dut.pacman.ghost_y=16;
                end else top_dut.game.ball_y=240;
                top_tick;
                if(top_dut.lives!==i || top_dut.state!==((i==0)?2:0))
                    $fatal(1,"Shared life loss: mode=%0d remaining=%0d",mode,i);
            end
            force top_dut.launch=1'b1; top_tick; release top_dut.launch;
            if(top_uo!==8'h4f || top_dut.state!==0)
                $fatal(1,"Shared session restart");
            if(mode==3 && (top_dut.pac_score!==0 || top_dut.pac_x!==16))
                $fatal(1,"Maze restart");
            if(mode!=3 && (top_dut.bricks!==32'hffffffff || top_dut.paddle!==112))
                $fatal(1,"Paddle engine restart");
        end
        top_ui=0;
        $display("PASS: DIP debounce, gamepad protocol/timeout, Breakout motion/collisions, Pong and Pacman motion");
        $finish;
    end
    initial begin #10000000; $fatal(1,"Unit-test timeout"); end
endmodule
