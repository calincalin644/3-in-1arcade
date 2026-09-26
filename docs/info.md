## How it works

The default game is Tiny Breakout, a one-player paddle-and-ball game. Destroy the 8 by 4 brick
field without losing all three lives. The ball bounces off the walls, bricks,
and paddle. Hitting the left or right half of the paddle changes the ball's
horizontal direction. The paddle moves at a constant speed while a direction
is held. Holding both directions stops it.

Set `ui_in[3]` high during reset to select Pong. Pong uses the same video timing
and controls, with the player paddle at the bottom and a simple CPU paddle at
the top. Launch starts a rally; missing either paddle costs a life. Set both
`ui_in[3]` and `ui_in[7]` high during reset to select the Pacman-style maze.
Pacman uses a constant tile map, pellets, a moving ghost and four-direction
gamepad controls without a framebuffer; launch starts a life.

Breakout and Pong share ball and player-paddle registers, movement arithmetic,
and common collision checks. One lives counter and session state machine serves
all three games. Only the selected engine advances, and only its loss/win events
reach the session controller. On the last lost life, game-over is immediate in
all games. Restart restores three lives and resets the selected game's objects.

The display uses standard Tiny VGA RGB222 wiring (64 available colors),
640x480 timing, and 320x240 logical coordinates. The input clock is 25.2 MHz:
800 clocks per line and 525 lines per frame give exactly 60 frames per second.
Horizontal sync is active low for pixels 656..751, and vertical sync for lines
490..491. RGB is black during blanking. Game updates occur in vertical blanking.
No framebuffer, external memory, or programmable palette is used. Bricks have
one-pixel logical mortar seams, alternating edge highlights and shadows, and a
small deterministic coordinate-based texture. The pattern repeats predictably,
so it costs only logic and remains stable across frames.

White blocks at the upper left show remaining lives. A red center bar means
game over; a green bar means all bricks were cleared. Launch/restart starts a
fresh game from either end state, and a second press launches its ball.

The onboard 7-segment display shows the selected game's remaining lives,
from 3 down to 0. VGA uses `uio_out[7:0]` on BIDIR with all eight output
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

RTL unit tests cover input conditioning and directed game states. The external
pin tests cover sync boundaries, blanking, initial colors, paddle movement and
launch, and can also run on the gate-level netlist.

## External hardware

- Tiny VGA RGB222 PMOD and VGA monitor.
- Optional Psychogenic SNES-compatible Gamepad PMOD and controller.
- Alternatively, three active-high buttons on INPUT, or the built-in DIP switches.
- ETR/FabricFox FPGA breakout for FPGA testing, or a matching Tiny Tapeout ASIC.
