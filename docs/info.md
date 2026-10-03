## How it works

Three games share one movement engine, a lives/session controller and VGA timing.
The project targets one Tiny Tapeout SKY130 tile and runs on the ETR demo board
with a FabricFox FPGA ASIC simulator. The current version is FPGA-tested; an
earlier revision hardened successfully, but the updated RTL needs a new run.

### Breakout

Clear all 16 bricks, arranged in eight columns and two rows, before losing three
lives. The paddle moves at constant speed while Left or Right is held; holding
both stops it. The ball bounces off the side and top walls, bricks and paddle.
Hitting the left or right paddle half sets the ball's horizontal direction.
A missed ball costs a life. Brick gaps are decorative: collision selects the
brick cell using the ball's leading vertical point.

Selecting Breakout through the demo-board helper leaves the ball on the paddle
until A, Start or BOOT is pressed. All sixteen bricks remain visible while
waiting. The former automatic serve could remove the bottom-right brick about
1.28 seconds after selection, making it appear absent at startup.

### Pong

The player controls the bottom paddle; the CPU paddle snaps to the ball's
32-logical-pixel column each frame. Collision uses the same column boundaries.
The CPU's horizontal rebound combines the impact-half bit with column parity
(`x[2] ^ x[3]` in the movement grid). This deterministic rule breaks the previous
default repeating rally without adding state. With an unmoved paddle, the default
serve now loses a life after about 3.43 seconds; other trajectories depend on play.
Missing either paddle costs a life. There is no separate score or win condition.

### Pacman-style maze

Pacman moves only while a direction is held and stops at the next movement
update after release. Turns are allowed at maze-cell boundaries. Between
boundaries, holding a direction continues the stored heading until a turn is
safe; at a boundary, a blocked requested direction stops movement. Simultaneous
directions have priority Left, Right, Up, then Down.

Pacman moves twice as fast as the red ghost. The ghost keeps moving when the
player stops and chooses legal directions toward the player. It avoids immediate
reversal when another opening exists, but can reverse at a dead end. This is a
local chase heuristic, not complete maze pathfinding.

Eat all **16 pellets** to win: fourteen yellow food dots and two cyan teleport pellets. They occupy maze columns 1, 5, 9, 13 and
rows 1, 3, 5, 7 (zero-based). The two cyan pellets are larger: lower-left at column 1,
row 7, and upper-right at column 13, row 1. Collecting either immediately
teleports the ghost to its initial cell, column 14, row 10,
facing left. The ghost remains red and resumes chasing on subsequent updates.
Pickup takes priority over contact in the same update; there is no lasting
immunity, vulnerability timer, fleeing mode or edible ghost.

The other fourteen pellets are ordinary food. Losing a life preserves collected
pellets, including either teleport pellet; restarting after victory or game over
restores all sixteen. Pacman is a solid yellow square with no mouth animation.
There is no separate score counter.

### Lives and game states

All games start with three lives. After a lost life, press launch again. A red
64×8 logical-pixel rectangle at (128,120) indicates game over. A green rectangle
indicates that all bricks or pellets were collected. From either end state,
press launch once to reset the game, release, then press again to start play.

The on-screen lives indicators are three separate white 4×4 logical-pixel
squares at (32,12), (40,12) and (48,12), displayed as 8×8 VGA pixels each.
One, two or three squares are shown for that many lives; none are shown at zero.
The onboard seven-segment display uses only horizontal segments:

| Lives | Lit segments |
| --- | --- |
| 3 | Bottom + middle + top (`d`, `g`, `a`) |
| 2 | Bottom + middle (`d`, `g`) |
| 1 | Bottom (`d`) |
| 0 | None |

Vertical segments and the decimal point remain off.

### Video and shared hardware

| Property | Current implementation |
| --- | --- |
| Clock / frame rate | 25.2 MHz / 60 Hz |
| VGA timing | 640×480 active, 800×525 total |
| Logical rendering coordinates | 320×240 |
| Colors | RGB222: 64 available colors, fixed game colors |
| Position grid | Four logical pixels per step; 64 horizontal positions in the playfield |
| Movement cadence | Paddles and Pacman every play frame; balls and ghost every second play frame |
| Bitmap storage | 16 shared bits for Breakout bricks or Pacman pellets |
| Position storage | Four shared 6-bit registers for ball/paddles or Pacman/ghost |
| Arithmetic | Shared 6-bit add/subtract datapath and registered result |
| Video output | RGB and both sync signals registered together |
| Memory / PLL / DSP blocks | None; no framebuffer |

RGB is black during blanking. Horizontal sync is active low at pixels 656–751,
and vertical sync at lines 490–491. Gameplay updates start in vertical blanking
and complete before the next active image. The sequential engine checks the
four neighbors of each maze character with one gameplay wall decoder; the
renderer has a separate wall lookup. Each arithmetic microstep computes and
then consumes its result on the following clock.

The six-bit brick probe stores collision information for Breakout and ghost
heading in bits [5:3] for Pacman. Its lower bits are not needed by Pacman now
that timed vulnerability has been removed. Teleportation uses existing position
and heading registers. The 16-bit brick/pellet bank has per-bit clear/reset logic.
`ena=0` pauses game-state updates; reset aborts an update. Video timing continues.
Mode selection is held until reset.

| Combined resource measurement | Current value |
| --- | ---: |
| Local SKY130 synthesis cell area | 9,419.0336 µm² |
| Flip-flops | 147 |
| FabricFox packed logic cells | 827 / 5,280 |
| FPGA final timing estimate | 31.73 MHz (25.2 MHz target passes) |

These are local synthesis and FPGA results, not current routed ASIC occupancy.
The previously hardened revision and its remaining warnings are described in
[verification notes](gate-level-verification.md).

## Controls and connections

Connect the Tiny VGA PMOD to **BIDIR**, and the optional Psychogenic Gamepad PMOD
to **INPUT**. One controller in connector **1** is enough; RTL ignores controller
2. Leave DIP 4/5/6 OFF when the PMOD drives latch, serial clock and data.
The loader selects `ASIC_MANUAL_INPUTS` and leaves the RP2350 BIDIR pins as inputs.

| Action | DIP/custom button | Controller 1 |
| --- | --- | --- |
| Left | ui[0], switch 0 | D-pad Left |
| Right | ui[1], switch 1 | D-pad Right |
| Pacman up/down | Hold switch 2: switch 0 = up, switch 1 = down | D-pad Up / Down |
| Launch/restart | ui[2], switch 2 OFF → ON | A or Start |

In Pacman, switch 2 selects the DIP movement axis: OFF gives left/right, ON
gives up/down. Release switches 0/1 before changing axis; both OFF stops the
player. Switch 2 still launches on a rising input, which is ignored during
normal play. Gamepad directions and the other games are unchanged. No additional
flip-flops are needed: the modifier uses the existing synchronizer and mode.

Switch numbers are zero-based. Left/right buttons retain two-stage synchronizers
but have no debounce; gameplay samples their levels at frame updates. The
DIP/custom launch button alone requires two matching frame samples. Hold its press or release for at
least 50 ms. Launch is edge-triggered, so holding it does not repeatedly launch.

Without the demo-board helper, choose the mode and reset with the clock running:

| Game | ui[3] / DIP 3 | ui[7] / DIP 7 |
| --- | --- | --- |
| Breakout | OFF | OFF |
| Pong | ON | OFF |
| Pacman | ON | ON |
| Reserved (RTL falls back to Breakout) | OFF | ON |

The Psychogenic protocol uses ui[4]=latch, ui[5]=serial clock and ui[6]=data.
The receiver samples rising serial-clock edges and commits the final 12 bits
on the rising latch edge, selecting controller 1 with the default two-controller
firmware. An all-ones report releases buttons immediately. After 63 frame
updates without a report (about 1.03–1.05 seconds), the watchdog also releases
them. Held reports arrive about once per second, so a half-second timeout would
interrupt valid movement. All six external control signals have two-stage
synchronizers.

### Demo-board helper

The helper provides game selection without pressing physical reset:

- Keep DIP 3/7 OFF; press Select+B for Breakout, Select+Y for Pong or Select+A
  for Pacman. Selection takes effect after all buttons are released, so
  Select+A cannot also start Pacman.
- Once the arcade is loaded, a valid DIP 3/7 change stable for 0.5 seconds also
  selects a game. The helper ignores the reserved setting. Unchanged DIPs do
  not override a gamepad selection.
- Selection resets the game and restores three lives. All games wait for a
  separate A, Start or BOOT press. VGA also resets briefly. Keep DIP 2 OFF
  until ready to start; its OFF-to-ON transition can also launch.
- From the board's factory test, BOOT loads the arcade and leaves it waiting;
  subsequent BOOT presses act as launch/restart. Keep DIP 2 OFF when using BOOT.

Install `scripts/arcade_boot.py` as `/arcade_boot.py`,
`scripts/arcade_gamepad.py` as `/arcade_gamepad.py`, and `scripts/run_game.py` as
`/arcade_run.py` on a board with the Tiny Tapeout SDK. The connected board's
`main.py` already calls `arcade_boot.install(tt)` after normal SDK startup.
The FPGA bitstream is `/bitstreams/tt_um_breakout.bin`. Updating the bitstream
does not install or update the Python helper files automatically.

The gamepad helper passively captures reports using PIO1 state machine 6. It
briefly releases the mode pins to read physical DIPs and only drives HIGH or
releases a pin to input, avoiding an active LOW against an ON switch. These
features run on the demo-board microcontroller and occupy no ASIC area. The
loader supports a shuttle index containing `tt_um_breakout`, but operation with
the manufactured ASIC has not yet been tested.

## How to test

1. Connect VGA to BIDIR and optionally the gamepad PMOD to INPUT, connector 1.
2. Load the project, use manual-input mode and a 25.2 MHz clock, and reset.
3. In Breakout, verify all sixteen bricks while waiting, then launch and check
   movement, brick removal, paddle rebounds and lost lives.
4. In Pong, launch with the paddle untouched: the default rally should miss.
   Move to intercept the ball and check CPU rebounds.
5. In Pacman, check held-direction movement, stopping on release and wall
   blocking. Collect either large pellet to teleport the ghost; collect all food
   for victory. Verify that life loss preserves food progress.
6. Check the VGA life squares, seven-segment horizontal bars, end-state colors and
   restart behavior. Release A/Start or DIP 2 between presses.

For a custom three-button INPUT PCB, connect normally-open switches from 3.3 V
to PMOD signal pins 1/2/3 (ui[0]/ui[1]/ui[2]), each with a 10 kohm pull-down to
GND. Share ground and keep DIP 0/1/2 OFF when using these buttons. Three buttons
cover paddle movement and launch; in Pacman, hold the launch button while
pressing left/right to move up/down. Release directions before changing axis.

### Automated verification

`make test` runs the input/gameplay unit tests, 10,000 reference frames for each
game, directed pellet/teleport tests and four external-pin video tests. Run
`python3 test/test_board_controls.py` separately for the nine helper tests.

| External-pin test | Coverage |
| --- | --- |
| Breakout/video | Every raster line's sync boundaries and blanking, initial image, directional controls and launch |
| Pong | Controller ordering, paddle movement, opposing directions, disconnect release, CPU tracking, visible moving ball and reset-only selection |
| Pacman movement/walls | Player/ghost movement, stop on release, Up/Down, return to the top wall, continued blocking and reset into Pong |
| Pacman pellets | Sparse food map, large pellet, collection, retained unvisited food, lives and red ghost after teleport |

Current unit/reference/pellet tests pass. All four external-pin tests passed
before the second teleport pellet was added; that small change has directed
coverage and a regenerated VGA screenshot, but its external-pin rerun is pending. Video samples are grouped in raster order and
unnecessary frame waits removed; the tests still use only package pins.
The latest four video tests ran in separate simulator processes with independent
build/result paths. They can also run against a matching gate-level netlist,
but the current revision still needs that verification after hardening.
Detailed fast tests cover all 16 brick cells, all 64 CPU impact positions,
the stationary-paddle Pong regression, teleport/contact priority, pause,
restart and collection of the final pellet. They complement the video checks;
they do not replace gate-level or physical verification.

## External hardware

- Tiny VGA RGB222 PMOD and VGA monitor.
- Optional Psychogenic SNES-compatible Gamepad PMOD and controller in connector 1.
- Alternatively, three active-high buttons or built-in DIPs for paddle controls.
- ETR/FabricFox FPGA ASIC simulator, or a matching Tiny Tapeout ASIC after fabrication.
