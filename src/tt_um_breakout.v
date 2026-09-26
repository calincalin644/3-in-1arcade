// SPDX-License-Identifier: Apache-2.0
`default_nettype none

// Shared 640x480 timing at 25.2 MHz (exactly 60 Hz), with 320x240 game coordinates.
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
    breakout_controls controls(clk, rst_n, frame, ui_in, left, right, launch, up, down);

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

    wire [7:0] paddle, cpu_paddle, ball_x, ball_y;
    wire [31:0] bricks;
    wire [1:0] lives, state;
    wire paddle_lost, paddle_won, pac_lost, restart;
    // One session controller for all games; one ball/paddle engine for both
    // Breakout and Pong. Only the selected movement engine advances.
    arcade_session session(clk, rst_n, ena, frame, launch,
        pacman_mode ? pac_lost : paddle_lost,
        !pacman_mode && paddle_won, lives, state, restart);
    paddle_game game(clk, rst_n, ena && !pacman_mode, frame,
        left, right, pong_mode, state, restart,
        paddle, cpu_paddle, ball_x, ball_y, bricks, paddle_lost, paddle_won);

    wire [7:0] pac_x, pac_y, ghost_x, ghost_y, pac_score;
    wire [2:0] pac_dir;
    wire pac_mouth;
    pacman_game pacman(clk, rst_n, ena && pacman_mode, frame,
                       left, right, up, down, launch, state, restart,
                       pac_x, pac_y, ghost_x, ghost_y, pac_dir, pac_mouth,
                       pac_score, pac_lost);

    wire [31:0] selected_bricks = pong_mode ? 32'b0 : bricks;

    wire [5:0] rgb_game, rgb_pacman;
    breakout_renderer renderer(h[9:1], v[8:1], active, pong_mode,
                               paddle, cpu_paddle, ball_x, ball_y,
                               selected_bricks, lives, state, rgb_game);
    pacman_renderer pac_renderer(h[9:1], v[8:1], active,
                                  pac_x, pac_y, ghost_x, ghost_y,
                                  pac_dir, pac_mouth, pac_score,
                                  lives, state, rgb_pacman);
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
    reg [6:0] segments;
    always @* begin
        // Active-high segments g..a; decimal point remains off.
        case (lives)
            0: segments = 7'b0111111;
            1: segments = 7'b0000110;
            2: segments = 7'b1011011;
            3: segments = 7'b1001111;
            default: segments = 7'b0000000;
        endcase
    end
    assign uo_out = {1'b0, segments};
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
    output wire left, right, launch, up, down
);
    reg [5:0] sync1, sync2;
    wire [5:0] raw = {ui[6:4], ui[2:0]};
    reg serial_prev, latch_prev;
    reg [11:0] shift;
    reg [4:0] pad;
    reg [6:0] age;
    reg [2:0] dip_previous, dip_stable;
    reg launch_previous;
    wire report = sync2[3] && !latch_prev;
    wire serial_rise = sync2[4] && !serial_prev;
    wire fire = dip_stable[2] | pad[2];
    wire unused = &{1'b0, ui[7], ui[3]};

    always @(posedge clk) begin
        if (!rst_n) begin
            sync1 <= 0; sync2 <= 0;
            serial_prev <= 0; latch_prev <= 0;
            shift <= 12'hfff; pad <= 0; age <= 127;
            dip_previous <= 0; dip_stable <= 0; launch_previous <= 0;
        end else begin
            sync1 <= raw; sync2 <= sync1;
            serial_prev <= sync2[4]; latch_prev <= sync2[3];
            if (serial_rise) shift <= {shift[10:0], sync2[5]};
            if (frame) begin
                // Two matching samples, 16.7 ms apart, qualify each DIP/button.
                dip_previous <= sync2[2:0];
                if (dip_previous[0] == sync2[0]) dip_stable[0] <= sync2[0];
                if (dip_previous[1] == sync2[1]) dip_stable[1] <= sync2[1];
                if (dip_previous[2] == sync2[2]) dip_stable[2] <= sync2[2];
                launch_previous <= fire;
                if (age != 127) age <= age + 1'b1;
                if (age >= 120) pad <= 0; // Disconnect/stale report: release buttons.
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
    assign left = dip_stable[0] | pad[0];
    assign right = dip_stable[1] | pad[1];
    assign up = pad[4];
    assign down = pad[3];
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

// Breakout and one-player Pong share the ball, player paddle, movement
// arithmetic and wall/paddle collisions. Bricks and the CPU remain specific
// to their respective games; pong_mode is held constant between resets.
module paddle_game (
    input wire clk, rst_n, ena, frame, left, right, pong_mode,
    input wire [1:0] state,
    input wire restart,
    output reg [7:0] paddle, cpu_paddle, ball_x, ball_y,
    output reg [31:0] bricks,
    output wire lost, won
);
    localparam SERVE=2'd0, PLAY=2'd1;
    reg dx_right, dy_down;
    wire [7:0] serve_y = pong_mode ? 8'd216 : 8'd217;
    wire [7:0] paddle_next = left == right ? paddle :
        (left ? ((paddle < 3) ? 8'd0 : paddle - 8'd3) :
                ((paddle > 221) ? 8'd224 : paddle + 8'd3));
    wire [7:0] cpu_next = ball_x[7:5] > cpu_paddle[7:5] && cpu_paddle < 224 ? cpu_paddle + 1'b1 :
                           ball_x[7:5] < cpu_paddle[7:5] && cpu_paddle > 0 ? cpu_paddle - 1'b1 : cpu_paddle;
    wire side = dx_right ? ball_x >= 253 : ball_x <= 2;
    wire [7:0] next_x = side ? ball_x :
        (dx_right ? ball_x + 1'b1 : ball_x - 1'b1);
    wire [7:0] next_y = dy_down ? ball_y + 8'd2 : ball_y - 8'd2;
    wire [7:0] leading_y = dy_down ? ball_y + 8'd4 : ball_y - 8'd4;
    wire [4:0] lookahead_index = {leading_y[4:3], next_x[7:5]};
    reg [4:0] brick_index;
    reg brick_hit;
    // Positions are stable between frames. Precompute the brick lookup so
    // the 32:1 read does not extend the frame-update critical path.
    always @(posedge clk) begin
        if (!rst_n) begin brick_index <= 0; brick_hit <= 0; end
        else begin
            brick_index <= lookahead_index;
            brick_hit <= leading_y >= 32 && leading_y < 64 && bricks[lookahead_index];
        end
    end
    wire [7:0] paddle_offset = ball_x - paddle;
    wire [7:0] cpu_offset = ball_x - cpu_paddle;
    wire player_hit = dy_down && ball_y >= 216 &&
        (pong_mode ? ball_y < 220 : ball_y < 218) && paddle_offset < 32;
    wire ceiling_hit = !dy_down && ball_y <= 26;
    wire cpu_hit = ceiling_hit && ball_y > 22 && cpu_offset < 32;
    assign lost = pong_mode ? (ball_y >= 236 || ball_y <= 4) : ball_y >= 235;
    assign won = !pong_mode && bricks == 0;

    always @(posedge clk) begin
        if (!rst_n) begin
            paddle <= 112; cpu_paddle <= 112; ball_x <= 128; ball_y <= serve_y;
            bricks <= 32'hffffffff;
            dx_right <= 1; dy_down <= pong_mode;
        end else if (ena && frame) begin
            paddle <= paddle_next;
            if (pong_mode) cpu_paddle <= cpu_next;
            if (restart) begin
                paddle <= 112; cpu_paddle <= 112; ball_x <= 128; ball_y <= serve_y;
                bricks <= 32'hffffffff;
            end else if (state == SERVE) begin
                ball_x <= paddle_next + 8'd16; ball_y <= serve_y;
                dx_right <= 1; dy_down <= pong_mode;
            end else if (state == PLAY && !lost && !won) begin
                ball_x <= next_x;
                if (side) dx_right <= !dx_right;
                if (!pong_mode && ceiling_hit) begin
                    dy_down <= 1;
                end else if (player_hit) begin
                    ball_y <= serve_y; dy_down <= 0;
                    dx_right <= paddle_offset[4];
                end else if (pong_mode && cpu_hit) begin
                    ball_y <= 26; dy_down <= 1;
                    dx_right <= cpu_offset[4];
                end else if (!pong_mode && brick_hit) begin
                    bricks[brick_index] <= 0;
                    dy_down <= !dy_down;
                end else ball_y <= next_y;
            end
        end
    end
endmodule

// A compact Pacman-style maze. The map is a constant, so it needs no RAM.
module pacman_game (
    input wire clk, rst_n, ena, frame, left, right, up, down, launch,
    input wire [1:0] state,
    input wire restart,
    output reg [7:0] pac_x, pac_y, ghost_x, ghost_y,
    output reg [2:0] pac_dir,
    output reg pac_mouth,
    output reg [7:0] score,
    output wire lost
);
    localparam SERVE=2'd0, PLAY=2'd1;
    localparam STOP=3'd0, LEFT=3'd1, RIGHT=3'd2, UP=3'd3, DOWN=3'd4;
    reg [2:0] wanted;
    reg [2:0] ghost_dir;

    function maze_wall;
        input [3:0] cx, cy;
        begin
            // Decode wall runs directly rather than indexing a row bitmap.
            // This shortens the cell -> legal direction -> position path.
            maze_wall = cx == 0 || cx == 15 || cy == 0 || cy >= 11 ||
                ((cy == 2 || cy == 10) && cx >= 4 && cx <= 11) ||
                ((cy == 3 || cy == 4 || cy == 8 || cy == 9) && cx == 8) ||
                ((cy == 4 || cy == 6 || cy == 8) && cx >= 4 && cx <= 6) ||
                (cy == 6 && cx >= 9 && cx <= 11);
        end
    endfunction

    wire [3:0] cell_x = pac_x[7:4];
    wire [3:0] cell_y = pac_y[7:4];
    wire aligned = pac_x[3:0] == 0 && pac_y[3:0] == 0;
    wire open_left = !maze_wall(cell_x - 1'b1, cell_y);
    wire open_right = !maze_wall(cell_x + 1'b1, cell_y);
    wire open_up = !maze_wall(cell_x, cell_y - 1'b1);
    wire open_down = !maze_wall(cell_x, cell_y + 1'b1);
    wire wanted_open = wanted == LEFT ? open_left :
                       wanted == RIGHT ? open_right :
                       wanted == UP ? open_up :
                       wanted == DOWN ? open_down : 1'b0;
    wire current_open = pac_dir == LEFT ? open_left :
                        pac_dir == RIGHT ? open_right :
                        pac_dir == UP ? open_up :
                        pac_dir == DOWN ? open_down : 1'b0;
    wire [2:0] move_dir = aligned ?
        (wanted != STOP && wanted_open ? wanted :
         (pac_dir != STOP && current_open ? pac_dir : STOP)) : pac_dir;
    wire [7:0] next_x = move_dir == LEFT ? pac_x - 2 :
                        move_dir == RIGHT ? pac_x + 2 : pac_x;
    wire [7:0] next_y = move_dir == UP ? pac_y - 2 :
                        move_dir == DOWN ? pac_y + 2 : pac_y;
    wire [3:0] ghost_cell_x = ghost_x[7:4];
    wire [3:0] ghost_cell_y = ghost_y[7:4];
    wire ghost_aligned = ghost_x[3:0] == 0 && ghost_y[3:0] == 0;
    wire ghost_open_left = !maze_wall(ghost_cell_x - 1'b1, ghost_cell_y);
    wire ghost_open_right = !maze_wall(ghost_cell_x + 1'b1, ghost_cell_y);
    wire ghost_open_up = !maze_wall(ghost_cell_x, ghost_cell_y - 1'b1);
    wire ghost_open_down = !maze_wall(ghost_cell_x, ghost_cell_y + 1'b1);
    wire [2:0] ghost_turn = ghost_cell_x != cell_x ?
        (ghost_cell_x > cell_x && ghost_open_left ? LEFT :
         ghost_cell_x < cell_x && ghost_open_right ? RIGHT :
         ghost_cell_y > cell_y && ghost_open_up ? UP :
         ghost_cell_y < cell_y && ghost_open_down ? DOWN :
         ghost_open_left ? LEFT : ghost_open_right ? RIGHT :
         ghost_open_up ? UP : ghost_open_down ? DOWN : STOP) :
        (ghost_cell_y > cell_y && ghost_open_up ? UP :
         ghost_cell_y < cell_y && ghost_open_down ? DOWN :
         ghost_open_left ? LEFT : ghost_open_right ? RIGHT :
         ghost_open_up ? UP : ghost_open_down ? DOWN : STOP);
    wire [2:0] ghost_move_dir = ghost_aligned ? ghost_turn : ghost_dir;
    wire [7:0] ghost_next_x = ghost_move_dir == LEFT ? ghost_x - 2 :
                              ghost_move_dir == RIGHT ? ghost_x + 2 : ghost_x;
    wire [7:0] ghost_next_y = ghost_move_dir == UP ? ghost_y - 2 :
                              ghost_move_dir == DOWN ? ghost_y + 2 : ghost_y;
    assign lost = pac_x[7:4] == ghost_x[7:4] &&
                     pac_y[7:4] == ghost_y[7:4];

    always @(posedge clk) begin
        if (!rst_n) begin
            pac_x <= 16; pac_y <= 16; ghost_x <= 224; ghost_y <= 160;
            pac_dir <= RIGHT; wanted <= RIGHT; pac_mouth <= 0;
            ghost_dir <= LEFT;
            score <= 0;
        end else if (ena && frame) begin
            if (left) wanted <= LEFT;
            else if (right) wanted <= RIGHT;
            else if (up) wanted <= UP;
            else if (down) wanted <= DOWN;
            case (state)
                SERVE: begin
                    // Respawn on the launch edge, outside the collision path.
                    if (launch) begin
                        pac_x <= 16; pac_y <= 16; ghost_x <= 224; ghost_y <= 160;
                        pac_dir <= RIGHT; wanted <= RIGHT; pac_mouth <= 0;
                        ghost_dir <= LEFT;
                    end
                end
                PLAY: begin
                    pac_dir <= move_dir;
                    pac_x <= next_x; pac_y <= next_y;
                    ghost_x <= ghost_next_x; ghost_y <= ghost_next_y;
                    if (ghost_aligned) ghost_dir <= ghost_turn;
                    pac_mouth <= !pac_mouth;
                    if (aligned) score <= score + 1'b1;
                end
                default: begin
                    if (restart) begin
                        pac_x <= 16; pac_y <= 16; ghost_x <= 224; ghost_y <= 160;
                        pac_dir <= RIGHT; wanted <= RIGHT; pac_mouth <= 0;
                        ghost_dir <= LEFT;
                        score <= 0;
                    end
                end
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
    input wire pac_mouth,
    input wire [7:0] score,
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
    wire pellet = in_maze && !wall && x[3:0] >= 7 && x[3:0] <= 8 &&
                  y[3:0] >= 7 && y[3:0] <= 8;
    // Characters use the 16-pixel maze cell plus local bits, avoiding wide
    // coordinate subtraction in the pixel critical path.
    wire [4:0] pac_cell_x = pac_x[7:4] + 2;
    wire [3:0] pac_cell_y = pac_y[7:4] + 1;
    wire pac_shape = x[8:4] == pac_cell_x && y[7:4] == pac_cell_y &&
                     x[3:0] >= 4 && x[3:0] <= 11 &&
                     y[3:0] >= 4 && y[3:0] <= 11;
    wire mouth_cut = pac_mouth && (x[2] ^ y[2]);
    wire [4:0] ghost_cell_x = ghost_x[7:4] + 2;
    wire [3:0] ghost_cell_y = ghost_y[7:4] + 1;
    wire ghost_shape = x[8:4] == ghost_cell_x && y[7:4] == ghost_cell_y &&
                       x[3:0] >= 4 && x[3:0] <= 11 &&
                       y[3:0] >= 4 && y[3:0] <= 11;
    wire life_icon = y[7:2] == 0 &&
        ((x[7:2] == 9 && lives >= 1) ||
         (x[7:2] == 11 && lives >= 2) ||
         (x[7:2] == 13 && lives >= 3));
    wire score_icon = y[7:2] == 1 &&
        ((x[7:2] == 20 && score >= 1) ||
         (x[7:2] == 22 && score >= 2) ||
         (x[7:2] == 24 && score >= 3) ||
         (x[7:2] == 26 && score >= 4));

    always @* begin
        rgb = 0;
        if (active) begin
            if (in_maze) begin
                if (wall)
                    rgb = (x[3] || y[3]) ? 6'b00_00_11 : 6'b00_01_11;
                else if (pellet) rgb = 6'b11_11_00;
            end
            if (ghost_shape) rgb = (x[2] ^ y[2]) ? 6'b11_00_00 : 6'b10_00_00;
            if (pac_shape && !mouth_cut) rgb = 6'b11_11_00;
            if (life_icon || score_icon) rgb = 6'b11_11_11;
            if (state[1] && x >= 120 && x < 200 && y >= 112 && y < 118)
                rgb = 6'b11_00_00;
        end
    end
endmodule

module breakout_renderer (
    input wire [8:0] x,
    input wire [7:0] y,
    input wire active,
    input wire pong_mode,
    input wire [7:0] paddle, cpu_paddle, ball_x, ball_y,
    input wire [31:0] bricks,
    input wire [1:0] lives, state,
    output reg [5:0] rgb
);
    // Playfield: x=32..287, with power-of-two brick indexing (32x8 cells).
    wire in_field = x >= 32 && x < 288;
    wire [7:0] px = x[7:0] - 8'd32;
    // Ball matching uses aligned cell/local bits instead of two full-width
    // subtractions, keeping the shared VGA path short with Pacman present.
    wire [4:0] ball_cell_x = ball_x[7:4] + 2;
    wire [3:0] ball_cell_y = ball_y[7:4];
    wire ball = x[8:4] == ball_cell_x && y[7:4] == ball_cell_y &&
                x[3:2] == ball_x[3:2] && y[3:2] == ball_y[3:2];
    wire [4:0] brick_index = {y[4:3], px[7:5]};
    wire brick_mortar = (px[4:0] == 0 || px[4:0] == 31 ||
                         y[2:0] == 0 || y[2:0] == 7);
    // A tiny deterministic cellular pattern acts like a coarse, repeatable
    // surface texture. It uses only coordinate bits: no ROM or framebuffer.
    wire brick_fractal = ((px[0] ^ px[2]) & (y[0] ^ y[1])) ^
                         ((px[1] & y[2]) | (px[3] ^ y[1]));
    wire brick_highlight = (px[1:0] == 0 && y[2:1] == 1) ||
                           (!brick_fractal && y[2:1] == 0);
    wire brick = y >= 32 && y < 64 && bricks[brick_index] &&
                 px[4:0] >= 1 && px[4:0] < 31 && y[2:0] >= 1 && y[2:0] < 7;
    wire [7:0] paddle_delta = px - paddle;
    wire life_icon = y[7:2] == 3 &&
        ((x[7:2] == 9 && lives >= 1) ||
         (x[7:2] == 11 && lives >= 2) ||
         (x[7:2] == 13 && lives >= 3));
    always @* begin
        rgb = 0;
        if (active) begin
            if (((x == 30 || x == 289) && y >= 24) ||
                (y == 24 && x >= 30 && x <= 289)) rgb = 6'b01_01_01;
            if (in_field) begin
                if (brick || (y >= 32 && y < 64 && bricks[brick_index] && brick_mortar)) begin
                    case (y[4:3])
                        0: rgb = brick_mortar ? 6'b01_00_00 :
                                (brick_highlight ? 6'b11_01_01 :
                                                     (brick_fractal ? 6'b10_00_01 : 6'b11_00_01));
                        1: rgb = brick_mortar ? 6'b01_01_00 :
                                (brick_highlight ? 6'b11_11_00 :
                                                     (brick_fractal ? 6'b10_01_00 : 6'b11_10_00));
                        2: rgb = brick_mortar ? 6'b00_01_00 :
                                (brick_highlight ? 6'b10_11_00 :
                                                     (brick_fractal ? 6'b00_10_00 : 6'b01_11_00));
                        3: rgb = brick_mortar ? 6'b00_01_01 :
                                (brick_highlight ? 6'b00_11_11 :
                                                     (brick_fractal ? 6'b00_10_10 : 6'b00_10_11));
                    endcase
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
                if (state[1] && x >= 120 && x < 200 && y >= 120 && y < 126)
                    rgb = state[0] ? 6'b00_11_00 : 6'b11_00_00;
            end
            if (life_icon) rgb = 6'b11_11_11;
        end
    end
endmodule
`default_nettype wire
