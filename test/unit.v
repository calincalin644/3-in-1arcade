`timescale 1ns/1ps
module unit;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, frame=0, ena=1;
    reg [7:0] ui=0;
    reg control_pacman=0;
    wire left, right, launch, up, down;
    breakout_controls controls(clk,rst_n,frame,ui,left,right,launch,up,down,control_pacman);
    reg gl=0, gr=0, gf=0;
    wire [5:0] paddle,bx,by;
    wire [15:0] bank;
    wire [15:0] bricks=bank[15:0];
    wire [1:0] lives,state;
    wire game_lost, game_won, game_done, game_launch;
    wire [5:0] unused_cpu;
    arcade_session game_session(clk,rst_n,ena,game_done,game_launch,game_lost,game_won,lives,state,);
    arcade_engine game(.clk(clk),.rst_n(rst_n),.ena(ena),.frame(frame),
        .left(gl),.right(gr),.up(1'b0),.down(1'b0),.launch(gf),
        .pong_mode(1'b0),.pacman_mode(1'b0),.state(state),
        .x(bx),.y(by),.a(paddle),.b(unused_cpu),.bricks(bank),.direction(),
        .lost(game_lost),.won(game_won),.done(game_done),.launch_saved(game_launch));
    reg pl=0, pr=0, pf=0;
    wire [5:0] pp, cp, pbx, pby;
    wire [1:0] plives, pstate;
    wire pong_lost, pong_won, pong_done, pong_launch;
    arcade_session pong_session(clk,rst_n,ena,pong_done,pong_launch,pong_lost,pong_won,plives,pstate,);
    arcade_engine pong(.clk(clk),.rst_n(rst_n),.ena(ena),.frame(frame),
        .left(pl),.right(pr),.up(1'b0),.down(1'b0),.launch(pf),
        .pong_mode(1'b1),.pacman_mode(1'b0),.state(pstate),
        .x(pbx),.y(pby),.a(pp),.b(cp),.bricks(),.direction(),
        .lost(pong_lost),.won(pong_won),.done(pong_done),.launch_saved(pong_launch));
    reg pal=0, par=0, pau=0, pad=0, paf=0;
    wire [5:0] pacx, pacy, ghostx, ghosty;
    wire [1:0] paclives, pacstate;
    wire [2:0] pacdir;
    wire pac_lost, pac_won, pac_done, pac_launch;
    arcade_session pac_session(clk,rst_n,ena,pac_done,pac_launch,pac_lost,pac_won,paclives,pacstate,);
    arcade_engine pac(.clk(clk),.rst_n(rst_n),.ena(ena),.frame(frame),
        .left(pal),.right(par),.up(pau),.down(pad),.launch(paf),
        .pong_mode(1'b0),.pacman_mode(1'b1),.state(pacstate),
        .x(pacx),.y(pacy),.a(ghostx),.b(ghosty),.bricks(),.direction(pacdir),
        .lost(pac_lost),.won(pac_won),.done(pac_done),.launch_saved(pac_launch));
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
        begin @(negedge clk); frame=1; clocks(1); @(negedge clk); frame=0; clocks(40); end
    endtask
    task top_tick;
        begin
            @(negedge clk); force top_dut.frame=1'b1; clocks(1);
            @(negedge clk); release top_dut.frame; clocks(40);
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
    reg [7:0] expected_bars;
    reg [15:0] maze_row;
    reg [4:0] saved_phase;
    initial begin
        reset;
        if(paddle!==28 || bx!==32 || state!==0 || lives!==3 || bricks!==16'hffff)
            $fatal(1,"Reset state");
        // Directions follow the synchronized input without any frame samples.
        ui[0]=1; clocks(4);
        if(!left || right) $fatal(1,"Synchronized left missing before frame");
        ui[0]=0; ui[1]=1; clocks(4);
        if(left || !right) $fatal(1,"Direction change waited for frame debounce");
        ui[0]=1; clocks(4);
        if(!left || !right) $fatal(1,"Both direction inputs");
        // Launch still rejects a one-frame bounce and requires matching samples.
        ui[2]=1; clocks(4); tick;
        if(launch) $fatal(1,"Launch accepted after only one sample");
        ui[2]=0; clocks(4); tick;
        if(launch) $fatal(1,"Launch bounce accepted");
        ui[2]=1; clocks(4); tick; tick;
        if(!launch) $fatal(1,"Launch edge missing");
        tick;
        if(launch) $fatal(1,"Held launch repeats");
        ui[2:0]=0; clocks(4); tick; tick; tick;
        // DIP-only Pacman: DIP 2 remaps 0/1 to up/down, without new state.
        control_pacman=1;
        for(i=0;i<8;i=i+1) begin
            ui[2:0]=i; clocks(4);
            if(left !== (ui[0] && !ui[2]) || right !== (ui[1] && !ui[2]) ||
               up !== (ui[0] && ui[2]) || down !== (ui[1] && ui[2]))
                $fatal(1,"Pacman DIP mapping %0d",i);
        end
        // A held modifier must not remap the independent gamepad directions.
        ui[2:0]=4; clocks(4);
        packet(24'h000020);
        if(!left || right || up || down) $fatal(1,"Modifier changed gamepad left");
        packet(24'h000040);
        if(left || right || up || !down) $fatal(1,"Modifier changed gamepad down");
        packet(24'hffffff);
        control_pacman=0;
        ui[2:0]=7; clocks(4);
        if(!left || !right || up || down) $fatal(1,"Other games remapped by launch");
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
        // The PMOD repeats held-button reports about once per second.
        for(i=0;i<3;i=i+1) begin
            repeat(60) tick;
            if(!left) $fatal(1,"One-second report interval released held button");
            packet(24'h000020);
        end
        repeat(62) tick;
        if(!left) $fatal(1,"Controller timed out before its deadline");
        tick;
        if(left) $fatal(1,"Stale controller held left");
        repeat(4) tick;
        if(left) $fatal(1,"Timeout counter wrapped");
        packet(24'h000020);
        if(!left) $fatal(1,"Report after timeout did not restore controls");
        packet(24'hffffff);
        if(left) $fatal(1,"Disconnected report did not release controls");

        // Coarse positions count four logical pixels. Paddles update each frame.
        reset; gl=1; repeat(60) tick;
        if(paddle!==0) $fatal(1,"Left clamp");
        gr=1; tick; if(paddle!==0) $fatal(1,"Opposed directions");
        gl=0; repeat(60) tick; gr=0;
        if(paddle!==56) $fatal(1,"Right clamp");
        gf=1; tick; gf=0;
        if(state!==1 || by!==54) $fatal(1,"Launch");
        ena=0; tick; if(by!==54) $fatal(1,"Disabled movement"); ena=1;
        @(negedge clk); game.x=32; game.y=40; game.direction=1; game.motion_phase=0;
        tick;
        if(bx!==33 || by!==39) $fatal(1,"First half-rate movement");
        tick;
        if(bx!==33 || by!==39) $fatal(1,"Movement should skip alternate frames");
        tick;
        if(bx!==34 || by!==38) $fatal(1,"Second half-rate movement");
        @(negedge clk); game.x=63; game.motion_phase=0;
        tick; if(game.direction[0]!==0 || bx!==63) $fatal(1,"Right wall");
        @(negedge clk); game.x=0; game.motion_phase=0;
        tick; if(game.direction[0]!==1 || bx!==0) $fatal(1,"Left wall");
        @(negedge clk); game.y=6; game.direction=1; game.motion_phase=0;
        tick; if(game.direction[1]!==1) $fatal(1,"Ceiling");
        // Every brick cell must be reachable, including all row boundaries.
        for(i=0;i<16;i=i+1) begin
            @(negedge clk); game.bricks=16'hffff;
            game.x=(i%8)*8+2; game.y=9+(i/8)*4;
            game.direction=1; game.motion_phase=0;
            tick;
            if(bricks!==(16'hffff ^ (16'b1<<i)) || game.direction[1]!==1)
                $fatal(1,"Coarse brick collision index %0d",i);
        end
        @(negedge clk); game.a=28; game.x=30; game.y=54; game.direction=3; game.motion_phase=0;
        tick; if(game.direction[1:0]!==0 || by!==54) $fatal(1,"Left paddle bounce");
        @(negedge clk); game.x=34; game.y=54; game.direction=3; game.motion_phase=0;
        tick; if(game.direction[1:0]!==1) $fatal(1,"Right paddle bounce");
        for(i=2;i>=0;i=i-1) begin
            @(negedge clk); game.y=59; game_session.state=1;
            tick;
            if(lives!==i || state!==((i==0)?2:0)) $fatal(1,"Life transition");
        end
        gf=1; tick; gf=0;
        if(state!==0 || lives!==3 || bricks!==16'hffff) $fatal(1,"Restart");
        // Keep the registered win behavior: final hit then win on next frame.
        @(negedge clk); game_session.state=1; game.bricks=16'h0001;
        game.x=2; game.y=9; game.direction=1; game.motion_phase=0;
        tick; if(bricks!==0 || state!==1) $fatal(1,"Final brick");
        tick; if(state!==3) $fatal(1,"Registered win timing");
        gf=1; tick; gf=0;
        if(state!==0 || lives!==3 || bricks!==16'hffff) $fatal(1,"Win restart");

        reset; pf=1; tick; pf=0;
        for(i=0;i<64;i=i+1) begin
            @(negedge clk); pong_session.state=1; pong.x=i;
            pong.y=6; pong.b=(i/8)*8; pong.direction=1; pong.motion_phase=0;
            tick;
            if(cp!==(i/8)*8 || pong.direction[1]!==1'b1 ||
               pong.direction[0]!==(((i/4) ^ (i/8)) & 1'b1) || pby!==6)
                $fatal(1,"Pong CPU bounce at x=%0d",i);
        end
        @(negedge clk); pong.x=15; pong.y=6; pong.b=16; pong.direction=1; pong.motion_phase=0;
        tick;
        if(pong.direction[1]!==0 || pby!==5 || cp!==8) $fatal(1,"Adjacent CPU column miss");
        @(negedge clk); pong.y=1; tick;
        if(plives!==2 || pstate!==0) $fatal(1,"Pong upper miss");
        @(negedge clk); pong_session.state=1; pong.y=59; tick;
        if(plives!==1 || pstate!==0) $fatal(1,"Pong lower miss");

        // The default serve must not sustain itself with a stationary paddle.
        reset; pf=1; tick; pf=0;
        for(i=0;i<210 && plives==3;i=i+1) tick;
        if(plives!==2 || pstate!==0) $fatal(1,"Pong default rally still self-sustains");

        // Collision map must match the displayed maze exactly.
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
        repeat(8) tick;
        if(pacx!==4 || pacy!==4 || (ghostx===56 && ghosty===40))
            $fatal(1,"Released player must stay put while ghost moves");
        par=1; repeat(4) tick; par=0;
        if(pacx!==8 || pacy!==4) $fatal(1,"Pacman one cell per four frames");
        // Release between cell boundaries, then resume in each heading.
        for(i=1;i<=4;i=i+1) begin
            @(negedge clk); pac.x=(i<=2)?9:4; pac.y=(i<=2)?4:9;
            pac.direction=i; pac.motion_phase=0;
            repeat(4) tick;
            if(pacx!==((i<=2)?9:4) || pacy!==((i<=2)?4:9))
                $fatal(1,"Release did not stop heading %0d",i);
            pal=(i==1); par=(i==2); pau=(i==3); pad=(i==4);
            tick;
            if(pacx!==((i==1)?8:(i==2)?10:4) || pacy!==((i==3)?8:(i==4)?10:4))
                $fatal(1,"Held direction did not resume heading %0d",i);
            pal=0; par=0; pau=0; pad=0;
        end
        // A perpendicular request cannot cut through a cell corner.
        @(negedge clk); pac.x=5; pac.y=4; pac.direction=2; pac.motion_phase=0;
        pad=1; repeat(3) tick;
        if(pacx!==8 || pacy!==4) $fatal(1,"Turn before cell boundary");
        tick;
        if(pacx!==8 || pacy!==5) $fatal(1,"Held turn not taken at boundary");
        pad=0;
        // A blocked request must not fall back to the previous heading.
        @(negedge clk); pac.x=4; pac.y=4; pac.direction=2; pac.motion_phase=0;
        pau=1; repeat(4) tick; pau=0;
        if(pacx!==4 || pacy!==4) $fatal(1,"Blocked request continued previous heading");
        @(negedge clk); pac.a=12*4; pac.b=10*4; pac.x=4; pac.y=4;
        pac.brick_probe[5:3]=1; pac.motion_phase=0;
        tick;
        if(pac.a[5:2]!==12 || pac.b[5:2]!==9) $fatal(1,"Ghost wall turn");
        // Player above row-2 wall: old chase bounced (5,3)<->(4,3).
        @(negedge clk); pac.x=20; pac.y=4; pac.a=20; pac.b=12;
        pac.brick_probe[5:3]=1; pac.motion_phase=0; pac_session.state=1;
        repeat(32) tick;
        if(ghostx!==12 || ghosty!==4) $fatal(1,"Ghost failed to go around wall");
        // When the only opening is behind it, the ghost must reverse.
        force pac.flags=4'b0010; force pac.brick_probe[5:3]=3'd1; #1;
        if(pac.ghost_turn!==3'd2) $fatal(1,"Ghost refused dead-end reversal");
        release pac.flags; release pac.brick_probe[5:3];
        @(negedge clk); pac.x=4; pac.y=4; pac.a=4; pac.b=4; pac_session.state=1;
        tick; if(paclives!==2 || pacstate!==0) $fatal(1,"Pacman life");
        // Inputs belong to the frame request, not the later ALU cycles.
        // Pausing in mid-transaction must hold both phase and position.
        gl=0; gr=1; reset;
        @(negedge clk); frame=1; clocks(1);
        @(negedge clk); frame=0; clocks(2);
        @(negedge clk); ena=0; gl=1; gr=0; saved_phase=game.phase;
        clocks(10);
        if(game.phase!==saved_phase || paddle!==28 || state!==0)
            $fatal(1,"Paused microsequence advanced");
        @(negedge clk); ena=1; clocks(40);
        if(paddle!==29 || bx!==33 || game.phase!==0)
            $fatal(1,"Mid-frame input change corrupted pending movement");
        gl=0;
        // Reset must abort any partially completed maze update.
        for(i=0;i<32;i=i+1) begin
            reset; @(negedge clk); pac_session.state=1; frame=1; clocks(1);
            @(negedge clk); frame=0; clocks(i);
            reset;
            if(pac.phase!==0 || pacx!==4 || pacy!==4 || ghostx!==56 || ghosty!==40 || paclives!==3)
                $fatal(1,"Reset failed to abort update at offset %0d",i);
        end
        // Integrated DIP-only maze control through synchronizers and engine.
        top_ui=8'h88; reset;
        top_ui=8'h8c; clocks(4); repeat(3) top_tick;
        if(top_dut.state!==1) $fatal(1,"DIP-only Pacman did not start");
        top_ui=8'h8e; clocks(4); repeat(8) top_tick;
        if(top_dut.grid_y<=4) $fatal(1,"DIP-only down did not move Pacman");
        my=top_dut.grid_y;
        top_ui=8'h8c; clocks(4); repeat(3) top_tick;
        if(top_dut.grid_y!==my) $fatal(1,"DIP-only release did not stop Pacman");
        top_ui=8'h8d; clocks(4); repeat(16) top_tick;
        if(top_dut.grid_y!==4) $fatal(1,"DIP-only up failed to reach top wall");
        top_ui=8'h8a; clocks(4); repeat(4) top_tick;
        if(top_dut.grid_x<=4) $fatal(1,"DIP-only right did not move Pacman");
        top_ui=8'h89; clocks(4); repeat(8) top_tick;
        if(top_dut.grid_x!==4) $fatal(1,"DIP-only left failed to reach left wall");
        top_ui=8'h88; reset;
        if({top_dut.pacman_mode,top_dut.pong_mode}!==2'b10) $fatal(1,"Pacman selector");
        top_ui=8'h08; reset;
        if({top_dut.pacman_mode,top_dut.pong_mode}!==2'b01) $fatal(1,"Pong selector");
        // The common life counter must drive the display in every mode,
        // including the reserved-mode fallback.
        for(mode=0;mode<4;mode=mode+1) begin
            top_ui = ((mode & 2) << 6) | ((mode & 1) << 3);
            reset;
            if(top_uo!==8'h49 || top_oe!==8'hff)
                $fatal(1,"Display reset or VGA output enables");
            if(top_dut.pos_x!==((mode==3)?16:128) || top_dut.aux_x!==((mode==3)?224:112))
                $fatal(1,"Shared position bank did not reset for selected game");
            if(mode==3 && (top_dut.engine.wanted!==3'd0 || top_dut.engine.ghost_dir!==3'd1))
                $fatal(1,"Shared probe direction initialization after mode switch");
            for(i=0;i<4;i=i+1) begin
                @(negedge clk);
                top_dut.session.lives=i;
                clocks(1);
                case(i)
                    0: expected_bars=8'h00;
                    1: expected_bars=8'h08;
                    2: expected_bars=8'h48;
                    3: expected_bars=8'h49;
                endcase
                if(top_uo!==expected_bars)
                    $fatal(1,"Wrong lives bars: mode=%0d lives=%0d out=%h", mode,i,top_uo);
            end
            force top_dut.launch=1'b1; top_tick; release top_dut.launch;
            if(top_dut.state!==1) $fatal(1,"Selected game did not launch");
            // Physical positions are shared. Selector changes during play
            // must not reinterpret that bank until reset is asserted.
            top_ui=~top_ui;
            top_tick;
            if(top_dut.pacman_mode!==(mode==3) || top_dut.pong_mode!==(mode==1))
                $fatal(1,"Game mode changed without reset");
            for(i=2;i>=0;i=i-1) begin
                @(negedge clk); top_dut.session.state=1;
                if(mode==3) begin
                    top_dut.engine.x=16; top_dut.engine.y=16;
                    top_dut.engine.a=16; top_dut.engine.b=16;
                end else top_dut.engine.y=60;
                top_tick;
                if(top_dut.lives!==i || top_dut.state!==((i==0)?2:0))
                    $fatal(1,"Shared life loss: mode=%0d remaining=%0d",mode,i);
            end
            force top_dut.launch=1'b1; top_tick; release top_dut.launch;
            if(top_uo!==8'h49 || top_dut.state!==0)
                $fatal(1,"Shared session restart");
            if(mode==3 && (top_dut.pac_x!==16 || top_dut.pac_y!==16))
                $fatal(1,"Maze restart");
            if(mode!=3 && (top_dut.bricks[15:0]!==16'hffff || top_dut.paddle!==112))
                $fatal(1,"Paddle engine restart");
        end
        top_ui=0;
        $display("PASS: synchronized directions, launch debounce, gamepad protocol/timeout, Breakout motion/collisions, Pong and Pacman motion");
        $finish;
    end
    initial begin #10000000; $fatal(1,"Unit-test timeout"); end
endmodule
