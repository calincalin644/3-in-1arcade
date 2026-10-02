## How it works

The default game is Tiny Breakout, a one-player paddle-and-ball game. Destroy the 8 by 2 brick
field without losing all three lives. The ball bounces off the walls, bricks,
and paddle. Hitting the left or right half of the paddle changes the ball's
horizontal direction. The paddle moves at a constant speed while a direction
is held. Holding both directions stops it.

Set `ui_in[3]` high during reset to select Pong. Pong uses the same video timing
and controls, with the player paddle at the bottom and a simple CPU paddle at
the top. The CPU snaps to the ball's 32-logical-pixel column each frame,
with collision checks on those same column boundaries. Launch starts a rally; missing either paddle costs a life. Set both
`ui_in[3]` and `ui_in[7]` high during reset to select the Pacman-style maze.
Pacman uses a constant tile map, 16 collectible pellets, a moving ghost and four-direction
gamepad controls without a framebuffer; launch starts a life. The player moves
only while a direction is held and stops at the next movement update after
release. Turns remain restricted to maze-cell boundaries: between boundaries,
a held direction continues the current heading until a turn is safe. At a
boundary, a blocked requested direction stops the player. Simultaneous directions
have priority left, right, up, then down; the ghost moves independently. It avoids immediately reversing when another
open route exists, allowing it to escape two-cell oscillation beside walls.
It again compares its position with the player to chase, or to flee while
vulnerable. This is local steering, not complete maze pathfinding.
The 16 pellets occupy maze columns 1, 5, 9, 13 and rows 1, 3, 5, 7
(zero-based).
Entering a pellet cell during play clears it. Eat all 16 to win (green status
bar). Losing a life retains collected pellets; restarting after win or game over
restores all 16. There is no separate score counter. The player is a solid yellow square without
mouth animation. One of the 16 pellets, at column 1 and row 7,
is a 6×6 logical-pixel power pellet; the other 15 pellets are 2×2. Eating it
starts a 240-frame (four-second) timer. The ghost turns cyan,
prefers open directions away from the player and may reverse to escape. Contact
while powered respawns the ghost without losing a life. A fresh power pickup
protects against contact in the same update. At timer expiry the ghost returns
to red and normal contact costs a life. Reset/restart clears the timer; `ena=0`
pauses it. The power pellet shares the existing bitmap and counts toward victory.

All three games use one sequential movement engine and one lives/session controller.
Four 6-bit position registers serve ball X/Y and paddle X positions in Breakout/Pong,
or player X/Y and ghost X/Y in Pacman. Movement and offset calculations use a shared
6-bit add/subtract datapath. A single gameplay wall decoder checks the eight maze
neighbors in successive operations; the renderer has its own wall lookup.
The six-bit brick collision probe holds `{hit, unused, row, column}` in Breakout
and doubles as ghost direction storage in bits [5:3] for Pacman. The player
request is decoded directly from the frame-latched buttons, without a separate
remembered request.
The 16-bit bitmap stores either Pacman pellets or Breakout bricks. The bitmap uses explicit
per-bit next-state logic for clear/reset,
avoiding a variable-index write mux while retaining the same collision priority.
Reset and respawn initialize the ghost direction; Breakout overwrites the probe
before using it. The current player heading remains stored to allow safe movement
between maze-cell boundaries.

Each stored position counts four rendering pixels, giving 64 horizontal
positions across the playfield. The renderer expands coordinates by appending
two zero bits. Paddles and Pacman update every PLAY frame by one grid unit;
balls and the ghost update every second PLAY frame. At 60 Hz, Pacman therefore
moves twice as fast as the ghost: one maze cell per four frames versus eight.
Controls and loss/win checks still run every frame. The 16 bricks form two taller rows in the same field area; paddle/ball sizes
and the maze layout remain unchanged.

Controls are captured at vertical blanking. Updates complete within 32 pixel clocks;
the renderer sees the completed positions before the next active frame. Each
operation takes two clocks to preserve timing. `ena=0` pauses an in-progress update,
and reset aborts it. Mode selection is held until reset. Game-over occurs on the
last lost life; restart restores three lives and resets the selected game's objects.

The display uses standard Tiny VGA RGB222 wiring (64 available colors),
640x480 timing, and 320x240 logical coordinates. The input clock is 25.2 MHz:
800 clocks per line and 525 lines per frame give exactly 60 frames per second.
Horizontal sync is active low for pixels 656..751, and vertical sync for lines
490..491. RGB is black during blanking. Game updates occur in vertical blanking.
No framebuffer, external memory, or programmable palette is used. Bricks use
flat row colors with black gaps. Maze walls and the ghost also use flat colors.
Decorative shading and the pellet-score indicator have been removed to save area.

White blocks at the upper left show remaining lives. A red center bar means
game over; a green bar means all bricks were cleared. Launch/restart starts a
fresh game from either end state, and a second press launches its ball.

The onboard 7-segment display shows the selected game's remaining lives as
horizontal bars: bottom for one, bottom + middle for two, all three for three,
and blank for zero. Vertical segments and the decimal point remain off. VGA uses `uio_out[7:0]` on BIDIR with all eight output
enables set; `uo_out[6:0]` drives segments a through g, and the decimal point
is off. Move the VGA PMOD from OUTPUT to BIDIR when upgrading an older build.
The loader leaves the RP2350 bidirectional pins as inputs.

### Controls

| Action | DIP/custom button | Controller 1 |
| --- | --- | --- |
| Move left | ui[0], switch 0 | Left |
| Move right | ui[1], switch 1 | Right |
| Pacman up/down | — | Up / Down |
| Launch/restart | ui[2], switch 2 OFF to ON | A or Start |

`ui[3]` and `ui[7]` are sampled while reset is asserted: `00` selects Breakout,
`01` selects Pong, and `11` selects Pacman. On the board these are DIP 3 and DIP
7. The gamepad remains on ui[4:6]; its U/D signals are used by Pacman.

Board switch labels are zero-based (0–7), matching ui[] indices.
Inputs are active high. DIP/buttons are synchronized and accepted after two
matching video-frame samples. Hold a press or release for at least 50 ms.
Launch is edge-triggered, so a held switch does not launch repeatedly.

The Psychogenic Gamepad PMOD uses ui[4]=latch, ui[5]=clock, ui[6]=data.
It is an input-only serial protocol: sample rising clock edges and commit the
last 12 bits on the rising latch edge. This selects controller 1 under the
default two-controller firmware configuration. A disconnected controller
reports all ones. Buttons also release after about two seconds without a report.

## How to test

1. Connect Tiny VGA to the BIDIR PMOD and a VGA monitor.
2. Optionally connect the Psychogenic Gamepad PMOD to INPUT.
3. Select the project in manual-input mode, start a 25,200,000 Hz project clock,
   and assert/release the synchronous active-low reset with the clock running.
4. Move the paddle with Left/Right or DIP switches 0/1. Press A/Start or toggle
   DIP 2 from OFF to ON to launch. Return DIP 2 to OFF before another launch.
5. Check brick removal, rebounds, lost lives and the red/green end-state bars.

For a custom three-button INPUT PMOD PCB, connect normally-open switches from
3.3 V to PMOD signal pins 1/2/3 (ui[0]/ui[1]/ui[2]), each with a 10 kohm pull-down
to GND. Share ground with the demoboard. Keep DIP 0/1/2 OFF when using buttons.
Keep DIP 4/5/6 OFF when the gamepad is connected. Manual-input mode prevents
the management microcontroller from driving these inputs.

RTL unit tests cover input conditioning, directed game states, frame input capture,
pausing and reset during an update. Reference simulations compare all three games
with behavioral reference engines over 10,000 frames each; the Pong reference
includes coarse CPU tracking. References use rendering-pixel coordinates with
the new movement rates; directed tests cover all 16 brick cells, all eight CPU
columns, and the alternate-frame movement cadence. The external
pin tests cover sync boundaries, blanking, initial colors, paddle movement and
launch. Additional cases select Pong and Pacman through reset pins, send serial
gamepad reports, check player/CPU paddles and ball motion, identify both maze
characters, exercise Up/Down and a blocking wall, and switch games via reset.
They verify that controller 2 is ignored, opposing directions stop the paddle,
and the disconnected-controller marker releases buttons. All three cases run
on RTL or the gate-level netlist using only package pins.

## External hardware

- Tiny VGA RGB222 PMOD and VGA monitor.
- Optional Psychogenic SNES-compatible Gamepad PMOD and controller.
- Alternatively, three active-high buttons on INPUT, or the built-in DIP switches.
- ETR/FabricFox FPGA breakout for FPGA testing, or a matching Tiny Tapeout ASIC.
