// SPDX-License-Identifier: Apache-2.0
// Pre-sequencing behavioral models, used only for simulation. COARSE_CPU
// enables the intentional coarse Pong tracking change; other physics are frozen.
// Shared life counter and serve/play/game-over/win state machine.
module reference_session (
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
module reference_paddle_game #(parameter COARSE_CPU=0) (
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
    wire [7:0] cpu_next = COARSE_CPU ? ((ball_x / 32) * 32) : ball_x[7:5] > cpu_paddle[7:5] && cpu_paddle < 224 ? cpu_paddle + 1'b1 :
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
    wire cpu_hit = ceiling_hit && ball_y > 22 && (COARSE_CPU ? ball_x / 32 == cpu_paddle / 32 : cpu_offset < 32);
    assign lost = pong_mode ? (ball_y >= 236 || ball_y <= 4) : ball_y >= 235;
    assign won = !pong_mode && bricks == 0;

    always @(posedge clk) begin
        if (!rst_n) begin
            paddle <= 112; cpu_paddle <= COARSE_CPU ? 8'd96 : 8'd112; ball_x <= 128; ball_y <= serve_y;
            bricks <= 32'hffffffff;
            dx_right <= 1; dy_down <= pong_mode;
        end else if (ena && frame) begin
            paddle <= paddle_next;
            if (pong_mode) cpu_paddle <= cpu_next;
            if (restart) begin
                paddle <= 112; cpu_paddle <= COARSE_CPU ? 8'd96 : 8'd112; ball_x <= 128; ball_y <= serve_y;
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
module reference_pacman_game (
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

