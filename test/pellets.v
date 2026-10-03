// Sixteen shared-bank pellets: collection, rendering, lives and restart.
`timescale 1ns/1ps
module pellets;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, ena=1, frame=0, launch=0;
    wire [5:0] x,y,a,b;
    wire [15:0] remaining;
    wire [1:0] lives,state;
    wire lost,won,done,launch_saved,frightened;
    arcade_engine engine(clk,rst_n,ena,frame,1'b0,1'b0,1'b0,1'b0,
        launch,1'b0,1'b1,state,x,y,a,b,remaining,,lost,won,done,launch_saved,frightened);
    arcade_session session(clk,rst_n,ena,done,launch_saved,lost,won,lives,state,);
    reg [8:0] pixel_x;
    reg [7:0] pixel_y;
    wire [5:0] rgb;
    // Characters on screen row zero leave the maze samples unobscured.
    pacman_renderer renderer(pixel_x,pixel_y,1'b1,8'd0,8'd240,8'd64,8'd240,
        3'd0,remaining,lives,state,frightened,rgb);
    task tick;
        begin
            @(negedge clk); frame=1;
            @(negedge clk); frame=0;
            repeat(40) @(negedge clk);
        end
    endtask
    task reset;
        begin rst_n=0; repeat(3) @(negedge clk); rst_n=1; end
    endtask
    integer i,j,c,r;
    reg [15:0] expected;
    initial begin
        reset;
        if(remaining!==16'hffff) $fatal(1,"Pellets not initialized");
        // Renderer shows exactly sixteen dots, all in traversable cells.
        for(r=0;r<12;r=r+1) for(c=0;c<16;c=c+1) begin
            pixel_x=32+c*16+7; pixel_y=16+r*16+7; #1;
            if(r<8 && r%2==1 && c%4==1) begin
                if(engine.maze_wall(c,r) || rgb!==6'b111100)
                    $fatal(1,"Missing/inaccessible pellet at %0d,%0d",c,r);
            end else if(rgb===6'b111100) $fatal(1,"Extra pellet at %0d,%0d",c,r);
        end
        // Only one dot extends to local pixel (5,5).
        for(r=1;r<8;r=r+2) for(c=1;c<15;c=c+1) begin
            pixel_x=32+c*16+5; pixel_y=16+r*16+5; #1;
            if(r==7 && c==1) begin
                if(rgb!==6'b111100) $fatal(1,"Power pellet not enlarged");
            end else if(rgb===6'b111100) $fatal(1,"Ordinary pellet enlarged");
        end
        // Player is a solid 8x8 square: no animated mouth cut-outs.
        for(r=4;r<12;r=r+1) for(c=36;c<44;c=c+1) begin
            pixel_x=c; pixel_y=r; #1;
            if(rgb!==6'b111100) $fatal(1,"Player has a mouth cut-out at %0d,%0d",c,r);
        end
        tick; if(remaining!==16'hffff) $fatal(1,"Pellet eaten before launch");
        launch=1; tick; launch=0;
        // No alias for rows below the pellet field or non-pellet columns.
        engine.x=4; engine.y=36; tick;
        engine.x=12; engine.y=4; tick;
        if(remaining!==16'hffff) $fatal(1,"Non-pellet cell cleared a bit");
        // Pause must protect the bank too.
        engine.x=4; engine.y=4; ena=0; tick; ena=1;
        if(remaining!==16'hffff) $fatal(1,"Disabled engine cleared pellet");
        expected=16'hffff;
        for(i=0;i<16;i=i+1) begin
            c=1+4*(i%4); r=1+2*(i/4);
            engine.x=c*4; engine.y=r*4; engine.a=56; engine.b=40;
            tick; expected=expected & ~(16'b1<<i);
            if(remaining!==expected) $fatal(1,"Wrong pellet cleared: %0d",i);
            pixel_x=32+c*16+7; pixel_y=16+r*16+7; #1;
            if(rgb!==0) $fatal(1,"Eaten pellet still drawn: %0d",i);
            if(i<15) begin
                tick;
                if(remaining!==expected || state!==1) $fatal(1,"Repeated visit or early win");
            end
        end
        tick;
        if(state!==3 || lives!==3) $fatal(1,"Final pellet did not win");
        pixel_x=128; pixel_y=120; #1;
        if(rgb!==6'b001100) $fatal(1,"Win indicator not green");
        launch=1; tick; launch=0;
        if(state!==0 || remaining!==16'hffff) $fatal(1,"Win restart did not refill pellets");
        launch=1; tick; launch=0; tick;
        expected=remaining;
        engine.power_high=0; engine.brick_probe[2:0]=0; engine.a=x; engine.b=y; tick;
        if(lives!==2 || state!==0 || remaining!==expected) $fatal(1,"Life loss reset pellets");
        launch=1; tick; launch=0;
        if(remaining!==expected) $fatal(1,"Respawn reset pellets");
        // Game-over restart refills the same bank.
        session.state=2; launch=1; tick; launch=0;
        if(remaining!==16'hffff || lives!==3 || state!==0) $fatal(1,"Game-over restart");
        // Fresh pickup protects even if the ghost occupies the same cell.
        reset; launch=1; tick; launch=0;
        engine.x=4; engine.y=28; engine.a=4; engine.b=28; engine.motion_phase=0; tick;
        if(lives!==3 || state!==1 || !frightened || engine.power_ticks!==120 ||
           a!==56 || b!==40 || remaining[12]!==0)
            $fatal(1,"Power pickup/contact priority or ghost respawn");
        pixel_x=101; pixel_y=5; #1;
        if(rgb!==6'b001111) $fatal(1,"Vulnerable ghost not cyan");
        tick;
        if(engine.power_ticks!==119) $fatal(1,"Consumed power pellet retriggered");
        ena=0; tick; ena=1;
        if(engine.power_ticks!==119) $fatal(1,"Power timer ran while disabled");
        // Former power pellets are now ordinary food and must not refresh the timer.
        for(i=0;i<3;i=i+1) begin
            engine.x=(i==0)?4:52; engine.y=(i<2)?12:28;
            engine.a=56; engine.b=40; tick;
            if(engine.power_ticks!==(119-((i+1)/2))) $fatal(1,"Ordinary pellet refreshed power timer");
        end
        // Frightened ghost prefers fleeing, including reversal in an open corridor.
        engine.x=4; engine.y=4; engine.a=20; engine.b=4;
        engine.brick_probe[5:3]=1; engine.motion_phase=0; tick;
        if(a!==21 || b!==4) $fatal(1,"Frightened ghost did not flee");
        // Expiration restores normal collision behaviour exactly at zero.
        repeat(234) begin engine.a=56; engine.b=40; tick; end
        if(engine.power_ticks!==1 || !frightened) $fatal(1,"Power duration shortened");
        engine.x=8; engine.y=4; engine.a=8; engine.b=4; tick;
        if(frightened || lives!==2 || state!==0) $fatal(1,"Power expiration collision");
        pixel_x=101; pixel_y=5; #1;
        if(rgb!==6'b110000) $fatal(1,"Ghost did not return to red");
        reset;
        if(frightened) $fatal(1,"Reset retained power timer");
        // Pickup on either cadence phase lasts 239 or 240 subsequent frames.
        for(i=0;i<2;i=i+1) begin
            reset; launch=1; tick; launch=0;
            engine.x=4; engine.y=28; engine.a=56; engine.b=40;
            engine.motion_phase=i; tick;
            if(engine.power_ticks!==120) $fatal(1,"Half-rate timer did not load");
            j=0;
            while(frightened && j<242) begin
                engine.a=56; engine.b=40; tick; j=j+1;
            end
            if(j!==(239+i) || engine.power_ticks!==0)
                $fatal(1,"Wrong half-rate duration, phase=%0d frames=%0d",i,j);
        end
        $display("PASS: 16 pellets, rendering, collection, no aliases, pause, win, lives, restart");
        $finish;
    end
    initial begin #1000000; $fatal(1,"Pellet test timeout"); end
endmodule
