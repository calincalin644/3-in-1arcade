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
Pacman uses a constant tile map, pellets, a moving ghost and four-direction
gamepad controls without a framebuffer; launch starts a life.

All three games use one sequential movement engine and one lives/session controller.
Four 6-bit position registers serve ball X/Y and paddle X positions in Breakout/Pong,
or player X/Y and ghost X/Y in Pacman. Movement and offset calculations use a shared
6-bit add/subtract datapath. A single gameplay wall decoder checks the eight maze
neighbors in successive operations; the renderer has its own wall lookup.
The six-bit brick collision probe holds `{hit, unused, row, column}` in Breakout
and doubles as Pacman direction storage: bits
[2:0] hold the requested player direction and [5:3] hold the ghost direction.
The 16-bit brick bitmap uses explicit per-bit next-state logic for clear/reset,
avoiding a variable-index write mux while retaining the same collision priority.
Reset and respawn initialize the directions; Breakout overwrites the probe
before using it. This removes separate direction registers without changing
movement or victory timing.

Each stored position counts four rendering pixels, giving 64 horizontal
positions across the playfield. The renderer expands coordinates by appending
two zero bits. Paddles update every frame by one grid unit; ball and maze
movement update every second PLAY frame by one grid unit. Controls and loss/win
checks still run every frame. Pacman and ghost average speed and ball vertical
speed are preserved, ball horizontal speed doubles, and paddles move one-third
faster. The 16 bricks form two taller rows in the same field area; paddle/ball sizes
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
launch, and can also run on the gate-level netlist.

## External hardware

- Tiny VGA RGB222 PMOD and VGA monitor.
- Optional Psychogenic SNES-compatible Gamepad PMOD and controller.
- Alternatively, three active-high buttons on INPUT, or the built-in DIP switches.
- ETR/FabricFox FPGA breakout for FPGA testing, or a matching Tiny Tapeout ASIC.
