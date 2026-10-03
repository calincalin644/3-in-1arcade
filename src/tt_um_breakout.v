// SPDX-License-Identifier: Apache-2.0
`default_nettype none

// Shared 640x480 timing at 25.2 MHz (60 Hz), with 320x240 rendering coordinates.
// Six-bit game positions count four rendering pixels; movement grid is 64x60.
module tt_um_breakout (
    input wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input wire ena, clk, rst_n
);
    wire [9:0] h, v;
    wire active, hs, vs, frame;
    breakout_video timing(clk, rst_n, h, v, active, hs, vs, frame);

    wire left, right, launch, up, down;
    breakout_controls controls(clk, rst_n, frame, ui_in, left, right, launch, up, down, pacman_mode);

    // ui_in[3] and ui_in[7] select the game. The gamepad occupies ui_in[4:6],
    // so the selector is sampled while reset is asserted and held during play.
    // 00 = Breakout, 01 = Pong, 11 = Pacman, 10 = reserved/Breakout.
    reg pong_mode, pacman_mode;
    always @(posedge clk) begin
        if (!rst_n) begin
            pong_mode <= !ui_in[7] && ui_in[3];
            pacman_mode <= ui_in[7] && ui_in[3];
        end
    end

    // Scale grid coordinates with wiring only; the engine arithmetic stays six bits.
    wire [5:0] grid_x, grid_y, grid_a, grid_b;
    wire [7:0] pos_x={grid_x,2'b0}, pos_y={grid_y,2'b0};
    wire [7:0] aux_x={grid_a,2'b0}, aux_y={grid_b,2'b0};
    wire [15:0] bricks;
    wire [1:0] lives, state;
    wire lost, won, done, launch_saved;
    wire [2:0] pac_dir;
    arcade_session session(clk, rst_n, ena, done, launch_saved,
                            lost, won, lives, state, /* restart unused */);
    arcade_engine engine(clk, rst_n, ena, frame, left, right, up, down,
        launch, pong_mode, pacman_mode, state,
        grid_x, grid_y, grid_a, grid_b, bricks, pac_dir,
        lost, won, done, launch_saved);
    // One physical bank: ball/Pacman (x,y), paddle/ghost-x (a), CPU/ghost-y (b).
    wire [7:0] paddle=aux_x, cpu_paddle=aux_y, ball_x=pos_x, ball_y=pos_y;
    wire [7:0] pac_x=pos_x, pac_y=pos_y, ghost_x=aux_x, ghost_y=aux_y;

    wire [15:0] selected_bricks = pong_mode ? 16'b0 : bricks[15:0];

    wire [5:0] rgb_game, rgb_pacman;
    breakout_renderer renderer(h[9:1], v[8:1], active, pong_mode,
                               paddle, cpu_paddle, ball_x, ball_y,
                               selected_bricks, lives, state, rgb_game);
    pacman_renderer pac_renderer(h[9:1], v[8:1], active,
                                  pac_x, pac_y, ghost_x, ghost_y,
                                  pac_dir,
                                  bricks, lives, state, rgb_pacman);
    wire [5:0] rgb = pacman_mode ? rgb_pacman : rgb_game;
    // Tiny VGA PMOD: {HS, B0, G0, R0, VS, B1, G1, R1}.
    // Register RGB and sync together to remove combinational output glitches.
    reg [7:0] video;
    always @(posedge clk) begin
        if (!rst_n) video <= 8'h88;
        else video <= {hs, rgb[0], rgb[2], rgb[4], vs, rgb[1], rgb[3], rgb[5]};
    end
    // VGA uses BIDIR so OUTPUT can drive the onboard seven-segment display.
    assign uio_out = video;
    assign uio_oe = 8'hff;
    // Active-high horizontal bars: a (top), g (middle), d (bottom).
    // 0 lives: blank; 1: bottom; 2: bottom+middle; 3: all three.
    assign uo_out = {1'b0, lives[1], 2'b0, (|lives), 2'b0, (&lives)};
    wire unused = &{1'b0, uio_in, h[0], v[9], v[0]};
endmodule

module breakout_video (
    input wire clk, rst_n,
    output reg [9:0] h, v,
    output wire active, hs, vs, frame
);
    always @(posedge clk) begin
        if (!rst_n) begin h <= 0; v <= 0; end
        else if (h == 799) begin
            h <= 0;
            v <= (v == 524) ? 10'd0 : v + 1'b1;
        end else h <= h + 1'b1;
    end
    assign active = h < 640 && v < 480;
    assign hs = !(h >= 656 && h < 752);
    assign vs = !(v >= 490 && v < 492);
    // Update game state at the start of vertical blanking to avoid tearing.
    assign frame = h == 0 && v == 480;
endmodule

module breakout_controls (
    input wire clk, rst_n, frame,
    input wire [7:0] ui,
    output wire left, right, launch, up, down,
    input wire pacman_mode
);
    reg [5:0] sync1, sync2;
    wire [5:0] raw = {ui[6:4], ui[2:0]};
    reg serial_prev, latch_prev;
    reg [11:0] shift;
    reg [4:0] pad;
    reg [5:0] age;
    reg dip_previous, dip_stable; // Launch only; directions use synchronized inputs.
    reg launch_previous;
    wire report = sync2[3] && !latch_prev;
    wire serial_rise = sync2[4] && !serial_prev;
    wire fire = dip_stable | pad[2];
    wire unused = &{1'b0, ui[7], ui[3]};

    always @(posedge clk) begin
        if (!rst_n) begin
            sync1 <= 0; sync2 <= 0;
            serial_prev <= 0; latch_prev <= 0;
            shift <= 12'hfff; pad <= 0; age <= 62;
            dip_previous <= 0; dip_stable <= 0; launch_previous <= 0;
        end else begin
            sync1 <= raw; sync2 <= sync1;
            serial_prev <= sync2[4]; latch_prev <= sync2[3];
            if (serial_rise) shift <= {shift[10:0], sync2[5]};
            if (frame) begin
                // Two matching frame samples qualify launch; directions bypass debounce.
                dip_previous <= sync2[2];
                if (dip_previous == sync2[2]) dip_stable <= sync2[2];
                launch_previous <= fire;
                if (age != 62) age <= age + 1'b1;
                if (age == 62) pad <= 0; // Disconnect/stale report: release buttons.
            end
            if (report) begin
                // Last 12 bits are controller 1: B,Y,Select,Start,U,D,L,R,A,X,L,R.
                // FFF is the PMOD's disconnected-controller marker.
                pad <= (shift == 12'hfff) ? 5'b0 :
                       {shift[7], shift[6], shift[8] | shift[3], shift[4], shift[5]};
                age <= 0;
            end
        end
    end
    // DIP 2 selects the vertical axis in Pacman; gamepad directions are unchanged.
    // Reuse the launch synchronizer and latched game mode: no extra state.
    wire vertical = pacman_mode && sync2[2];
    assign left = vertical ? pad[0] : (pad[0] | sync2[0]);
    assign right = vertical ? pad[1] : (pad[1] | sync2[1]);
    assign up = vertical ? (pad[4] | sync2[0]) : pad[4];
    assign down = vertical ? (pad[3] | sync2[1]) : pad[3];
    // Sampled by the game at frame; held launch never auto-launches another life.
    assign launch = fire && !launch_previous;
endmodule

// Shared life counter and serve/play/game-over/win state machine.
module arcade_session (
    input wire clk, rst_n, ena, frame, launch, lost, won,
    output reg [1:0] lives, state,
    output wire restart
);
    localparam SERVE=2'd0, PLAY=2'd1, OVER=2'd2, WON=2'd3;
    assign restart = state[1] && launch;
    always @(posedge clk) begin
        if (!rst_n) begin lives <= 3; state <= SERVE; end
        else if (ena && frame) begin
            case (state)
                SERVE: if (launch) state <= PLAY;
                PLAY: begin
                    if (won) state <= WON;
                    else if (lost) begin
                        lives <= lives - 1'b1;
                        state <= lives == 1 ? OVER : SERVE;
                    end
                end
                default: if (launch) begin lives <= 3; state <= SERVE; end
            endcase
        end
    end
endmodule

// One position bank and one 6-bit movement ALU serve all three games.
// A frame request starts a bounded sequence during vertical blanking. The
// session controller commits lives/state only when done is asserted.
module arcade_engine (
    input wire clk, rst_n, ena, frame,
    input wire left, right, up, down, launch, pong_mode, pacman_mode,
    input wire [1:0] state,
    output reg [5:0] x, y, a, b,
    output reg [15:0] bricks,
    output reg [2:0] direction,
    output reg lost, won,
    output wire done, launch_saved
);
    localparam SERVE=2'd0, PLAY=2'd1;
    localparam STOP=3'd0, LEFT=3'd1, RIGHT=3'd2, UP=3'd3, DOWN=3'd4;
    localparam IDLE=5'd0, PLAYER_CHECK=5'd1, CPU_CHECK=5'd2,
        PLAYER_STEP=5'd3, CPU_STEP=5'd4, SERVE_BALL=5'd5,
        BALL_X=5'd6, BRICK_CHECK=5'd7, BALL_Y=5'd8,
        G_SCAN=5'd16, P_SCAN=5'd20, G_CHOOSE=5'd24, P_CHOOSE=5'd25,
        G_STEP=5'd26, P_STEP=5'd27, FINISH=5'd31;
    // Binary encoding avoids a flip-flop per microstep.
    (* fsm_encoding = "none" *) reg [4:0] phase;
    reg alu_ready;
    // IDLE toggles this on PLAY frames. Pacman uses the old value there;
    // CPU_STEP uses the new value later in the same update.
    reg motion_phase; // Half-rate ball/maze updates; inputs sampled every frame.
    reg [4:0] buttons;
    // Maze: {down,up,right,left}; paddles: {CPU direction,CPU hit,
    // player direction,player hit}. These uses never overlap.
    reg [3:0] flags;
    reg [5:0] brick_probe;
    // Same physical bits: brick collision probe or ghost direction in [5:3].
    // Requests come only from this frame; released directions are not queued.
    wire [2:0] wanted = buttons[0] ? LEFT : buttons[1] ? RIGHT :
                        buttons[2] ? UP : buttons[3] ? DOWN : STOP;
    wire [2:0] ghost_dir = brick_probe[5:3];
    assign done = phase == FINISH && alu_ready;
    assign launch_saved = buttons[4];
    wire [5:0] serve_y = 6'd54;
    wire aligned = x[1:0] == 0 && y[1:0] == 0;
    wire ghost_aligned = a[1:0] == 0 && b[1:0] == 0;
    wire side = direction[0] ? x >= 63 : x == 0;

    // Exactly one gameplay wall decoder. Four neighbors of each character
    // are queried on consecutive clocks; the visible maze map is unchanged.
    function maze_wall;
        input [3:0] cx, cy;
        begin
            maze_wall = cx == 0 || cx == 15 || cy == 0 || cy >= 11 ||
                ((cy == 2 || cy == 10) && cx >= 4 && cx <= 11) ||
                ((cy == 3 || cy == 4 || cy == 8 || cy == 9) && cx == 8) ||
                ((cy == 4 || cy == 6 || cy == 8) && cx >= 4 && cx <= 6) ||
                (cy == 6 && cx >= 9 && cx <= 11);
        end
    endfunction
    wire scanning = phase[4:3] == 2'b10;
    wire [5:0] probe_x = phase[2] ? x : a;
    wire [5:0] probe_y = phase[2] ? y : b;
    reg [1:0] source_select;
    wire [5:0] alu_a = source_select[1] ? (source_select[0] ? b : a) :
                                           (source_select[0] ? y : x);
    reg [5:0] alu_b;
    reg subtract;
    wire [5:0] alu_value = alu_a + (alu_b ^ {6{subtract}}) + {5'b0, subtract};
    // Each microstep computes, then consumes the result on the next clock.
    // This separates operand selection/addition from collision/map decoding.
    reg [5:0] alu_result;
    always @* begin
        source_select = 0; alu_b = 0; subtract = 0;
        case (phase)
            PLAYER_CHECK: begin source_select=0; alu_b=a; subtract=1; end
            PLAYER_STEP: begin source_select=2; alu_b=buttons[0] ? 6'h3f : 6'd1; end
            SERVE_BALL: begin source_select=2; alu_b=6'd4; end
            BALL_X: begin source_select=0; alu_b=direction[0] ? 6'd1 : 6'h3f; end
            BRICK_CHECK: begin source_select=1; alu_b=direction[1] ? 6'd1 : 6'h3f; end
            BALL_Y: begin source_select=1; alu_b=direction[1] ? 6'd1 : 6'h3f; end
            G_STEP: begin
                source_select = {1'b1, (ghost_dir == UP || ghost_dir == DOWN)};
                alu_b = (ghost_dir == RIGHT || ghost_dir == DOWN) ? 6'd1 : 6'h3f;
            end
            P_STEP: begin
                source_select = {1'b0, (direction == UP || direction == DOWN)};
                alu_b = (direction == RIGHT || direction == DOWN) ? 6'd1 : 6'h3f;
            end
            default: begin
                if (scanning) begin
                    source_select = {!phase[2], phase[1]};
                    alu_b = phase[0] ? 6'd4 : 6'h3c;
                end
            end
        endcase
    end
    wire [3:0] query_x = phase[1] ? probe_x[5:2] : alu_result[5:2];
    wire [3:0] query_y = phase[1] ? alu_result[5:2] : probe_y[5:2];
    wire query_open = !maze_wall(query_x, query_y);
    wire [3:0] brick_index = {alu_result[2], x[5:3]};
    wire wanted_open = wanted == LEFT ? flags[0] : wanted == RIGHT ? flags[1] :
                       wanted == UP ? flags[2] : wanted == DOWN ? flags[3] : 1'b0;
    // Avoid two-cell oscillation beside walls; reverse only at a dead end.
    wire [3:0] ghost_forward = flags &
        {ghost_dir != UP, ghost_dir != DOWN, ghost_dir != LEFT, ghost_dir != RIGHT};
    wire [3:0] ghost_options = (|ghost_forward) ? ghost_forward : flags;
    wire [2:0] ghost_turn = (a[5:2] > x[5:2]) && ghost_options[0] ? LEFT :
        (a[5:2] < x[5:2]) && ghost_options[1] ? RIGHT :
        (b[5:2] > y[5:2]) && ghost_options[2] ? UP :
        (b[5:2] < y[5:2]) && ghost_options[3] ? DOWN :
        ghost_options[0] ? LEFT : ghost_options[1] ? RIGHT : ghost_options[2] ? UP : ghost_options[3] ? DOWN : STOP;

    // Explicit per-brick next-state logic avoids a variable-index write mux.
    // Reset/restart restores the bank; only an unmasked brick collision clears
    // its selected bit. Paddle and top-wall collisions retain their priority.
    wire brick_reset = phase == IDLE && frame && state[1] && launch;
    // Base 16: columns 1,5,9,13 at rows 1,3,5,7.
    // The same bank stores bricks or pellets, never both simultaneously.
    wire pellet_cell = !y[5] && y[2] &&
        x[3:2] == 2'b01;
    wire [3:0] pellet_index = {y[4:3],x[5:4]};
    wire pellet_clear = pacman_mode && phase == IDLE && frame && state == PLAY && pellet_cell;
    // Large teleport pellets: lower-left (index 12), upper-right (index 3).
    wire power_eaten = pellet_clear &&
        ((bricks[12] && pellet_index == 4'd12) || (bricks[3] && pellet_index == 4'd3));
    wire ghost_contact = x[5:2] == a[5:2] && y[5:2] == b[5:2];
    wire [3:0] clear_index = pacman_mode ? pellet_index : brick_probe[3:0];
    wire brick_clear = phase == BALL_Y && alu_ready && !pong_mode && brick_probe[5] &&
                       !(!direction[1] && y <= 6) && !flags[0];
    genvar bi;
    generate for (bi=0; bi<16; bi=bi+1) begin: brick_storage
        always @(posedge clk) begin
            if (!rst_n) bricks[bi] <= 1'b1;
            else bricks[bi] <= (ena && brick_reset) ||
                (bricks[bi] && !(ena && (brick_clear || pellet_clear) && clear_index == bi));
        end
    end endgenerate

    always @(posedge clk) begin
        if (!rst_n) begin
            phase <= IDLE; buttons <= 0; flags <= 0; brick_probe <= {LEFT, STOP};
            alu_result <= 0; alu_ready <= 0; motion_phase <= 0;
            x <= pacman_mode ? 6'd4 : 6'd32;
            y <= pacman_mode ? 6'd4 : serve_y;
            a <= pacman_mode ? 6'd56 : 6'd28;
            b <= pacman_mode ? 6'd40 : (pong_mode ? 6'd24 : 6'd28);
            direction <= pacman_mode ? RIGHT : {1'b0, pong_mode, 1'b1};
            lost <= 0; won <= 0;
        end else if (ena) begin
            alu_result <= alu_value;
            alu_ready <= phase == IDLE ? 1'b0 : !alu_ready;
            if (phase == IDLE || alu_ready) case (phase)
                IDLE: if (frame) begin
                    buttons <= {launch, down, up, right, left};
                    if (state == PLAY) motion_phase <= !motion_phase;
                    else motion_phase <= 0;
                    lost <= pacman_mode ? (ghost_contact && !power_eaten) :
                        (pong_mode ? (y >= 59 || y <= 1) : y >= 59);
                    won <= !pong_mode && bricks == 0;
                    if (pacman_mode) begin
                        if ((state == SERVE || state[1]) && launch) begin
                            x<=4; y<=4; a<=56; b<=40;
                            direction<=RIGHT; brick_probe[5:3] <=LEFT;
                            phase<=FINISH;
                        end else if (state == PLAY) begin
                            if (power_eaten) begin
                                // Large pellet teleports the ghost; pickup wins over contact.
                                a<=56; b<=40; brick_probe[5:3]<=LEFT;
                                phase<=aligned ? P_SCAN : P_STEP;
                            end else begin
                                // Player steps every frame; ghost every other frame.
                                phase <= motion_phase ? (aligned ? P_SCAN : P_STEP) :
                                    (ghost_aligned ? G_SCAN : G_STEP);
                            end
                        end else phase <= FINISH;
                    end else if (state[1] && launch) begin
                        x<=32; y<=serve_y; a<=28; b<=pong_mode ? 6'd24 : 6'd28;
                        phase<=FINISH;
                    end else phase<=PLAYER_CHECK;
                end
                PLAYER_CHECK: begin
                    flags[0] <= direction[1] && y == 54 && alu_result[5:3] == 0;
                    flags[1] <= alu_result[2]; phase<=CPU_CHECK;
                end
                CPU_CHECK: begin
                    // The rendered CPU paddle occupies one whole 32-pixel bin.
                    flags[2] <= !direction[1] && y == 6 && x[5:3] == b[5:3];
                    // Alternate the rebound rule across CPU columns to break
                    // the default stationary-paddle rally; no extra state.
                    flags[3] <= x[2] ^ x[3]; phase<=PLAYER_STEP;
                end
                PLAYER_STEP: begin
                    if (buttons[0] != buttons[1])
                        a <= buttons[0] && a == 0 ? 6'd0 :
                             buttons[1] && a >= 56 ? 6'd56 : alu_result;
                    phase<=CPU_STEP;
                end
                CPU_STEP: begin
                    // Coarse tracking: snap to the ball's current 32-pixel
                    // column. Low bits stay zero, matching the drawn paddle.
                    if (pong_mode) b <= {x[5:3],3'b0};
                    if (state == SERVE) phase<=SERVE_BALL;
                    else if (state == PLAY && !lost && !won && motion_phase) phase<=BALL_X;
                    else phase<=FINISH;
                end
                SERVE_BALL: begin
                    x<=alu_result; y<=serve_y; direction<={1'b0,pong_mode,1'b1};
                    phase<=FINISH;
                end
                BALL_X: begin
                    if (side) direction[0]<=!direction[0]; else x<=alu_result;
                    phase<=BRICK_CHECK;
                end
                BRICK_CHECK: begin
                    brick_probe <= {alu_result >= 8 && alu_result < 16 && bricks[brick_index], 1'b0, brick_index};
                    phase<=BALL_Y;
                end
                BALL_Y: begin
                    if (!pong_mode && !direction[1] && y <= 6) direction[1]<=1;
                    else if (flags[0]) begin
                        y<=serve_y; direction[1:0]<={1'b0,flags[1]};
                    end else if (pong_mode && flags[2]) begin
                        y<=6; direction[1:0]<={1'b1,flags[3]};
                    end else if (!pong_mode && brick_probe[5]) begin
                        direction[1]<=!direction[1];
                    end else y<=alu_result;
                    phase<=FINISH;
                end
                G_SCAN, G_SCAN+1, G_SCAN+2, G_SCAN+3,
                P_SCAN, P_SCAN+1, P_SCAN+2, P_SCAN+3: begin
                    flags <= {query_open,flags[3:1]};
                    if (phase[1:0] == 3) phase <= phase[2] ? P_CHOOSE : G_CHOOSE;
                    else phase <= phase + 1'b1;
                end
                G_CHOOSE: begin brick_probe[5:3] <=ghost_turn; phase<=G_STEP; end
                G_STEP: begin
                    if (ghost_dir==LEFT || ghost_dir==RIGHT) a<=alu_result;
                    else if (ghost_dir==UP || ghost_dir==DOWN) b<=alu_result;
                    phase<=aligned ? P_SCAN : P_STEP;
                end
                P_CHOOSE: begin
                    direction <= wanted_open ? wanted : STOP;
                    phase<=P_STEP;
                end
                P_STEP: begin
                    // Stop even between cells, retaining heading so a later
                    // held request can reach the next safe turning boundary.
                    if (|buttons[3:0]) begin
                        if (direction==LEFT || direction==RIGHT) x<=alu_result;
                        else if (direction==UP || direction==DOWN) y<=alu_result;
                    end
                    phase<=FINISH;
                end
                default: phase<=IDLE;
            endcase
        end
    end
endmodule

module pacman_renderer (
    input wire [8:0] x,
    input wire [7:0] y,
    input wire active,
    input wire [7:0] pac_x, pac_y, ghost_x, ghost_y,
    input wire [2:0] pac_dir,
    input wire [15:0] pellets,
    input wire [1:0] lives, state,
    output reg [5:0] rgb
);
    function [15:0] maze_mask;
        input [3:0] row;
        begin
            case (row)
                0: maze_mask=16'hffff; 1: maze_mask=16'h8001;
                2: maze_mask=16'h8ff1; 3: maze_mask=16'h8101;
                4: maze_mask=16'h8171; 5: maze_mask=16'h8001;
                6: maze_mask=16'h8e71; 7: maze_mask=16'h8001;
                8: maze_mask=16'h8171; 9: maze_mask=16'h8101;
                10: maze_mask=16'h8ff1; default: maze_mask=16'hffff;
            endcase
        end
    endfunction
    wire in_maze = x >= 32 && x < 288 && y >= 16 && y < 208;
    wire [4:0] col_wide = x[8:4] - 2;
    wire [3:0] col = col_wide[3:0];
    wire [3:0] row = y[7:4] - 1;
    wire [15:0] map_bits = maze_mask(row);
    wire wall = in_maze && map_bits[col];
    wire pellet_cell = !row[3] && row[0] &&
        col[1:0] == 2'b01;
    wire [3:0] pellet_index = {row[2:1],col[3:2]};
    wire power_pellet = pellet_index == 4'd12 || pellet_index == 4'd3;
    wire small_dot = x[3:0] >= 7 && x[3:0] <= 8 && y[3:0] >= 7 && y[3:0] <= 8;
    wire large_dot = x[3:0] >= 5 && x[3:0] <= 10 && y[3:0] >= 5 && y[3:0] <= 10;
    wire pellet = in_maze && pellet_cell && pellets[pellet_index] &&
        (power_pellet ? large_dot : small_dot);
    // Characters use the 16-pixel maze cell plus local bits, avoiding wide
    // coordinate subtraction in the pixel critical path.
    wire [4:0] pac_cell_x = pac_x[7:4] + 2;
    wire [3:0] pac_cell_y = pac_y[7:4] + 1;
    wire pac_shape = x[8:4] == pac_cell_x && y[7:4] == pac_cell_y &&
                     x[3:0] >= 4 && x[3:0] <= 11 &&
                     y[3:0] >= 4 && y[3:0] <= 11;
    wire [4:0] ghost_cell_x = ghost_x[7:4] + 2;
    wire [3:0] ghost_cell_y = ghost_y[7:4] + 1;
    wire ghost_shape = x[8:4] == ghost_cell_x && y[7:4] == ghost_cell_y &&
                       x[3:0] >= 4 && x[3:0] <= 11 &&
                       y[3:0] >= 4 && y[3:0] <= 11;
    // Three 4x4 life squares, spaced eight pixels apart at (32,12).
    wire life_icon = y[7:2] == 3 && x[8:5] == 1 && !x[2] && x[4:3] < lives;
    always @* begin
        rgb = 0;
        if (active) begin
            if (in_maze) begin
                if (wall)
                    rgb = 6'b00_00_11;
                else if (pellet) rgb = power_pellet ? 6'b00_11_11 : 6'b11_11_00;
            end
            if (ghost_shape) rgb = 6'b11_00_00;
            if (pac_shape) rgb = 6'b11_11_00;
            if (life_icon) rgb = 6'b11_11_11;
            if (state[1] && x[8:6] == 3'd2 && y[7:3] == 5'd15)
                rgb = state[0] ? 6'b00_11_00 : 6'b11_00_00;
        end
    end
endmodule

module breakout_renderer (
    input wire [8:0] x,
    input wire [7:0] y,
    input wire active,
    input wire pong_mode,
    input wire [7:0] paddle, cpu_paddle, ball_x, ball_y,
    input wire [15:0] bricks,
    input wire [1:0] lives, state,
    output reg [5:0] rgb
);
    // Playfield: x=32..287, with power-of-two brick indexing (32x16 cells).
    wire in_field = x >= 32 && x < 288;
    wire [7:0] px = x[7:0] - 8'd32;
    // Ball matching uses aligned cell/local bits instead of two full-width
    // subtractions, keeping the shared VGA path short with Pacman present.
    wire [4:0] ball_cell_x = ball_x[7:4] + 2;
    wire [3:0] ball_cell_y = ball_y[7:4];
    wire ball = x[8:4] == ball_cell_x && y[7:4] == ball_cell_y &&
                x[3:2] == ball_x[3:2] && y[3:2] == ball_y[3:2];
    wire [3:0] brick_index = {y[4], px[7:5]};
    wire brick = y >= 32 && y < 64 && bricks[brick_index] &&
                 px[4:0] >= 1 && px[4:0] < 31 && y[3:0] >= 1 && y[3:0] < 15;
    wire [7:0] paddle_delta = px - paddle;
    // Three 4x4 life squares, spaced eight pixels apart at (32,12).
    wire life_icon = y[7:2] == 3 && x[8:5] == 1 && !x[2] && x[4:3] < lives;
    always @* begin
        rgb = 0;
        if (active) begin
            if (((x == 30 || x == 289) && y >= 24) ||
                (y == 24 && x >= 30 && x <= 289)) rgb = 6'b01_01_01;
            if (in_field) begin
                if (brick) begin
                    rgb = y[4] ? 6'b00_10_11 : 6'b11_00_01;
                end
                if (pong_mode) begin
                    if (px[7:5] == cpu_paddle[7:5] && y[7:2] == 5)
                        rgb = 6'b11_00_11;
                    if (paddle_delta[7:5] == 0 && y[7:2] == 55)
                        rgb = 6'b00_11_11;
                    if (ball && state < 2) rgb = 6'b11_11_11;
                end else begin
                    if (paddle_delta[7:5] == 0 && y[7:2] == 55) rgb = 6'b00_11_11;
                    if (ball && state < 2) rgb = 6'b11_11_11;
                end
                // Central status bar: red = game over; green = all bricks cleared.
                if (state[1] && x[8:6] == 3'd2 && y[7:3] == 5'd15)
                    rgb = state[0] ? 6'b00_11_00 : 6'b11_00_00;
            end
            if (life_icon) rgb = 6'b11_11_11;
        end
    end
endmodule
`default_nettype wire
