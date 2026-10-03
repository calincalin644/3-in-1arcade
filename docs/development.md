# Design and development notes

Detailed implementation and verification notes for the 16-brick revision with
horizontal life bars and decoded brick writes.

A small Verilog Breakout game for the **Tiny Tapeout ETR/FabricFox FPGA kit**,
also prepared for **SKY130 GitHub Actions hardening with a 1x1 tile target**.

![Simulation of the VGA output](preview.png)

Classic black background, 16 flat colored bricks, a cyan paddle, a white ball and
three lives. Black gaps separate the bricks; decorative texture and shading have
been removed to reduce ASIC area.
Hold left/right to move at constant speed; opposing directions stop the paddle.
Press launch to serve. After losing a life, release and press launch again.
A red bar means game over; a green bar means you cleared all bricks. Press
launch once to reset an end state and again to launch the new ball.
Set `ui_in[3]` high while reset is asserted to select Pong. Pong uses the same
VGA timing, RGB222 output, input decoder and three-button/gamepad controls; the
lower paddle is the player and the upper paddle is a simple CPU opponent.
The CPU snaps to the ball's 32-logical-pixel column once per frame; collision
checks use the same column boundaries.
Set both `ui_in[3]` and `ui_in[7]` high during reset to select the third game,
a compact Pacman-style maze with pellets, a moving ghost and a controllable
yellow character. Both characters obey the maze walls. The maze is a constant
map and uses no framebuffer.

All games now use one sequenced movement engine, one lives/session controller,
and four shared 6-bit position registers. In Breakout/Pong those registers hold
ball X/Y and player/CPU paddle X; in Pacman they hold player X/Y and ghost X/Y.
One 6-bit add/subtract datapath performs movement and collision arithmetic over
successive clocks. Pacman's eight neighbor checks use one gameplay wall decoder.
The VGA renderer keeps its own maze lookup for continuous pixel generation.
Positions use a 64x60 movement grid across the existing 256x240 logical-pixel
playfield. Each grid unit is four rendering pixels (eight VGA pixels); appending
two zero bits converts positions for rendering. VGA timing, paddle/ball sizes and the maze layout remain unchanged. Breakout
now has eight columns and two taller rows: 16 bricks occupy the same field area.

Inputs and paddles update at 60 Hz. Ball and maze movement update at 30 Hz.
Paddles move four logical pixels per frame instead of three. Ball X/Y each
advance four logical pixels per movement tick: vertical speed is unchanged,
horizontal speed doubles. Pacman and ghost average speed remains unchanged.
The ball serve height is aligned to logical Y=216 for both paddle games.
The six-bit `brick_probe` register is also shared: Breakout uses it for the
brick index and hit flag; Pacman uses bits [2:0] for the requested direction
and bits [5:3] for the ghost direction. Reset/respawn initializes Pacman's
directions, and Breakout writes a fresh probe before every collision decision.

Inputs are captured at the start of vertical blanking. The longest update completes
within 32 pixel clocks (1.27 microseconds at 25.2 MHz), well before visible video
resumes. Each operation has a compute clock and a consume clock. Disabling `ena`
pauses the sequence; reset aborts it. Switching games still requires reset.
Ghost chase rules, controller decoding, and VGA timing remain. Bricks, maze walls
and the ghost use flat colors. The decorative pellet-score indicator and its
counter have been removed; lives indicators and mouth animation remain.

Reducing Breakout from 32 bricks to 16 lowers the local SKY130 estimate from
10,396 to 9,445 square micrometers (9.1%), with mapped flip-flops decreasing from
169 to 153. Each brick is 32x16 rendering pixels; the field is still 256x32 pixels.
The registered win flag and shared brick-probe/direction storage remain. The
shared six-bit probe now holds `{hit, unused, row, column}` in Breakout and the
same two three-bit directions in Pacman.

A subsequent rewrite replaces the variable-index brick write with explicit
per-bit next-state logic. The bitmap still contains 16 flip-flops, but the write
logic is smaller. The seven-segment display now uses horizontal life bars.
Together these changes lower the local mapped estimate from 9,445.3088 to
9,252.6240 square micrometers (2.04%), retaining all three games and all 16 bricks.
The engine rewrite is formally equivalent to the preceding version. The display
change is intentional: 0/1/2/3 lives drive segment masks 00/08/48/49 (hex).

The bar decoder alone maps to 12.5120 square micrometers, compared with 23.7728
for digits. Whole-design mapping is heuristic: replacing just the display gave
9,475.3376, so decoder savings cannot simply be subtracted from the chip total.
The combined brick-write/bar variant measured 9,252.6240 using the same recipe.

These estimates are useful only for relative comparisons. The preceding 32-brick
revision reached global routing with a 0.05 ns hold margin, but failed placement
during antenna repair. The later 16-brick revision with decoded writes and life
bars completed hardening; see the verified result below.

The onboard 7-segment display shows the selected game's remaining lives as
horizontal bars: bottom for one, bottom + middle for two, all three for three,
and blank for zero. Vertical segments and the decimal point remain off. VGA uses `uio_out[7:0]` on BIDIR with all eight output
enables set; `uo_out[6:0]` drives segments a through g, and the decimal point
is off. Move the VGA PMOD from OUTPUT to BIDIR when upgrading an older build.
The loader leaves the RP2350 bidirectional pins as inputs.

## Connections and controls

Connect a Tiny VGA RGB222 PMOD to **BIDIR**. All colors use its standard pinout.
Connect the Psychogenic Gamepad PMOD to **INPUT**, or use the DIP switches or a
custom three-button PCB:

| Action | DIP switch / input | Gamepad controller 1 |
| --- | --- | --- |
| Left | 0 / ui[0] | Left |
| Right | 1 / ui[1] | Right |
| Pacman up/down | — | Up / Down |
| Launch/restart | 2 / ui[2], OFF to ON | A or Start |

Switch labels are zero-based (0–7), matching the ui[] indices.
Hold button presses/releases for at least 50 ms. Gamepad signals are
ui[4]=latch, ui[5]=clock, ui[6]=data. The final 12 bits are controller 1 under
the default PMOD firmware. The other controller is ignored. Disconnected and
stale controllers release their buttons automatically.

The two-bit game selector is sampled during reset and held until the next reset:
`{ui_in[7],ui_in[3]}` selector bits `00` select Breakout, `01` select Pong, and `11`
select Pacman. On the board these are DIP 7 and DIP 3 respectively; leave both
OFF for Breakout, turn DIP 3 ON for Pong, or turn both ON for Pacman.

Use **ASIC_MANUAL_INPUTS** mode: the input signals belong to the switches/PMOD,
while the RP2350 still supplies clock and reset. Keep DIP 4/5/6 OFF with a gamepad
attached. With a custom PCB, keep DIP 0/1/2 OFF and use normally-open buttons
from 3.3 V to signal pins 1/2/3, with a 10 kohm pull-down on each input and common
ground. The optional pass-through connector on the gamepad PMOD allows sharing
the unused signals with a button PCB.

## Run on the FPGA

This workspace already contains `build/tt_um_breakout.bin`. From `/home/calin/git/TT`:

```sh
source scripts/local-env.sh
make -C breakout upload PORT=/dev/ttyACM0
```

Close Commander or other serial connections first. The loader copies the
bitstream to `/bitstreams`, detects the FPGA, selects it, switches to manual
inputs, starts **25,200,000 Hz**, and resets the game. It leaves the existing
startup default unchanged. The board needs its Tiny Tapeout MicroPython SDK.

An earlier build was programmed on the connected board and reported a
25,200,000 Hz project clock. The latest area-saving build needs to be uploaded. Without a VGA monitor attached, only the FPGA load and clock setup could
be checked here; connect a monitor to verify the image and use the DIP switches.

From a standalone copy of this directory, activate OSS CAD Suite, install
`mpremote` in your Python environment, then use `make upload`. `make` builds the
FPGA bitstream using the ETR/FabricFox pin map. It is not for the classic breakout.

VGA uses 800 clocks by 525 lines, giving exactly 60 Hz at 25.2 MHz. Logical game
pixels are doubled to 640x480 output. Do not use the counter demo's 1 MHz clock.

## Tests and preview

```sh
make test
```

Requires Icarus Verilog and `pip install -r test/requirements.txt` in your active
environment. For the extracted tools in this workspace, use:

```sh
source scripts/local-env.sh
make -C breakout test COMPILE_ARGS="-B $PWD/.tools/local/usr/lib/x86_64-linux-gnu/ivl"
```

The RTL unit test covers DIP debounce, serial controller decoding, stale reports,
movement limits, launch, collision cases, lost lives, win, restart, and
frame input capture, pausing, reset during an update, and shared-bank mode changes.
A separate regression compares all three games with behavioral reference engines
for 10,000 frames each, including disabled frames and restarts. The independent references
use rendering-pixel coordinates and model the new movement rates. Directed tests
cover all 16 brick cells, all eight CPU columns and alternate-frame movement. Cocotb tests
inspect the external pins for sync boundaries on every line, blanking, initial
graphics, opposing directions, movement and launch. Additional external-pin
cases select Pong and Pacman, drive complete two-controller gamepad reports,
and check movement, controller release, wall blocking and reset-based selection.
They work on the gate-level netlist without accessing internal registers. Simulation uses a
40 ns clock for convenience; timing assertions are in pixel clocks, and hardware
is built and run at 25.2 MHz.

`test/render.v` captures each game's initial frame from the real simulated VGA
output pins. `+MODE=0/1/2` selects Breakout/Pong/Pacman using the reset inputs;
`+OUTPUT=...` sets the PPM filename. Regenerate the README screenshots from the
repository root (ImageMagick provides `convert`):

```sh
mkdir -p build
iverilog -g2012 -s render -o build/render test/render.v src/tt_um_breakout.v
vvp build/render +MODE=0 +OUTPUT=build/preview.ppm
vvp build/render +MODE=1 +OUTPUT=build/pong.ppm
vvp build/render +MODE=2 +OUTPUT=build/pacman.ppm
convert build/preview.ppm docs/preview.png
convert build/pong.ppm docs/pong.png
convert build/pacman.ppm docs/pacman.png
```

The screenshots are simulation output, not artist's mockups.

## GitHub Actions / SKY130

Use **the contents of this `breakout/` directory as the root of a new repository**.
Do not nest it under another `breakout/` folder on GitHub. This keeps the existing
hex-counter project separate. Include `.github/workflows/`, `src/`, `test/`,
`docs/`, `fpga/`, `scripts/`, `info.yaml`, `Makefile`, `README.md`, and `LICENSE`.
Exclude build products, `.tools/`, Python caches, and simulation build directories.

1. Review the author field and module name in `info.yaml`. Use a unique module
   name for a real submission, updating the source, testbench, FPGA wrapper,
   Makefile and loader together if you rename it.
2. Enable GitHub Pages with **GitHub Actions** as its source.
3. Push the files. Workflows run RTL tests, build the 25.2 MHz FPGA bitstream,
   and run SKY130 GDS generation, precheck, gate-level tests and the viewer.
4. Check every job, especially timing and physical verification. Download
   `tt_submission` for the ASIC files and `fabricfox-breakout` for the FPGA binary.

The GDS/docs/test workflows come from the official SKY template at commit
`83d305501d505b157cd6e9ba87bc8ffd949526fd` and use `ttsky26d` actions.
The FPGA workflow builds this project's wrapper at the actual pixel-clock rate.
`src/config.json` also constrains ASIC timing to 39.68 ns (approximately 25.2 MHz),
replacing the template's unnecessary 20 ns / 50 MHz constraint. Tile dimensions
and placement density have not been changed.

`PL_RESIZER_HOLD_SLACK_MARGIN` and `GRT_RESIZER_HOLD_SLACK_MARGIN` are both
0.05 ns. Lowering the post-CTS margin from 0.1 ns reduced hold-repair buffering
from 85 to 23 cells in the preceding run, allowing it to reach global routing.
It then failed detailed placement during antenna repair. Hold repair, antenna
repair and final timing checks remain enabled.

## Verification and limits

- RTL unit tests and external video/control simulation have passed locally.
- FPGA synthesis, placement and routing passed at 25.2 MHz (29.14 MHz reported
  maximum); the design uses 863 of 5,280 FPGA logic cells.
- An early SKY130 mapping estimates about 9,253 square micrometers of standard
  cells with all three games. This is a rough synthesis estimate using OpenROAD's SKY130 HD typical
  library, not Tiny Tapeout signoff: it excludes clock-tree and physical overhead.
- **1x1 hardening passed for commit `299f5d5`**, including routing, DRC, LVS,
  antenna checks, setup/hold checks, Tiny Tapeout precheck and gate-level simulation.
  Nonfatal maximum-slew warnings remain; details below.
- Physical VGA display/controller testing is pending; the generated image is
  from simulation. No numeric score, sound, acceleration or framebuffer is included.

The game uses simple frame-based collision rules: the ball's leading vertical
point selects a brick cell; the tiny gaps between drawn bricks are decorative.
Paddle collisions use the current frame's ball center and paddle position.

References: [Tiny Tapeout pinouts](https://tinytapeout.com/specs/pinouts/),
[Psychogenic Gamepad PMOD](https://github.com/psychogenic/gamepad-pmod),
[SKY template](https://github.com/TinyTapeout/ttsky-verilog-template).

## Verified hardening result

[GitHub Actions run 36261694960](https://github.com/calincalin644/3-in-1arcade/actions/runs/36261694960),
26 September 2026, built commit `299f5d5fac2e06ec00606644f5cad34ce7e7af3f`.
Verified against the user-provided `logs_98196576803.zip`, which contains the
GDS, precheck, gate-level test and viewer job logs. This commit includes all
three games, 16 bricks, decoded brick writes and bottom-up horizontal life bars.

| Check / measurement | Result |
| --- | --- |
| Tile | 1×1, 161 × 111.52 µm die, 16,493.318 µm² core |
| Actual flow synthesis cell area | 11,494.7744 µm² |
| Global-placement reported utilization | 82.536% (includes placer area adjustments; not final routed occupancy) |
| Detailed routing | Completed with zero final routing violations |
| Antenna | Zero net/pin violations; passed |
| Magic DRC / Netgen LVS | Passed |
| Setup / hold checkers | No violations reported |
| Maximum capacitance checker | No violations reported |
| Tiny Tapeout precheck | Passed, including its separate layout checks |
| Gate-level VGA/control test | 1 passed, 0 failed |
| Viewer and submission artifacts | Generated and uploaded |

The flow's final summary reports nonfatal maximum-slew violations in
`max_ss_100C_1v60`, `max_tt_025C_1v80`, `min_ss_100C_1v60`,
`min_tt_025C_1v80`, `nom_ss_100C_1v60` and `nom_tt_025C_1v80`.
The console does not include enough per-net detail to quantify these warnings;
inspect the final STA reports in `GDS_logs` for the affected paths and magnitudes.
The successful workflow is therefore not described as free of all electrical
warnings. The main flow skips KLayout DRC; the separate Tiny Tapeout precheck
runs its own layout checks and passed.

The 9,252.6240 µm² figure elsewhere is the earlier local synthesis estimate,
not the actual flow's synthesis area or routed occupancy. No final cell-area
percentage is inferred from the global-placement utilization.

The [tt_submission artifact](https://github.com/calincalin644/3-in-1arcade/actions/runs/36261694960/artifacts/10912098425)
contains the ASIC deliverables. This result establishes successful hardening
for the recorded commit; fabrication/submission acceptance and physical display
validation are separate steps.


### Additional gate-level coverage

After the successful CI run, the exact routed netlist from `tt_submission.zip`
also passed the new Pong and Pacman/gamepad cases locally. Both cases passed
against RTL as well. See [coverage and reproducibility](gate-level-verification.md).
The recorded CI result above remains the original one-test result; these are
additional local results, and subsequent CI runs will execute all three cases.

### Held-direction Pacman controls (3 October 2026)

The player request now comes from the frame-latched direction buttons rather
than the lower three bits of `brick_probe`. Releasing all directions inhibits
player position writes, including between cell boundaries. The current heading
is retained between boundaries so that resuming with a perpendicular request
can reach a safe turning point. At a boundary, the held request is selected if
open; a blocked request stops the player instead of continuing the old heading.
The ghost still moves independently. Breakout and Pong retain their controls.

An identical local Yosys/SKY130 HD synthesis recipe measured 9,252.6240 µm²
before and 9,235.1072 µm² after the change: 17.5168 µm² (0.19%) smaller, with
153 flip-flops in both builds. This is a local synthesis comparison, not a
prediction of final routed area. The FPGA build uses 862 of 5,280 logic cells
and meets 25.2 MHz (final nextpnr estimate 29.05 MHz, seed 10).

Focused tests cover stopping and resuming in all four headings, stationary
players with moving ghosts, safe turns, blocked requests and reset. Each game
also passed 10,000 frames against the reference model, updated for the new maze
controls. All three external-pin VGA/gamepad tests passed, including the new
D-pad release/stop check. The seven board-helper host tests passed. The generated FPGA bitstream
is `build/tt_um_breakout.bin`; building it does not update the connected board.
This RTL revision needs fresh hardening and gate-level verification; the earlier
successful layout and gate-level results retain the previous movement behavior.

### Sixteen collectible pellets experiment (3 October 2026)

Pacman now shares Breakout's 16-bit bitmap. Pellet positions form a regular
4-by-4 pattern at maze columns 1/5/9/13 and rows 1/3/5/7; all are open and
reachable from spawn. Indexing these coordinates keeps the decoding small.
During PLAY, entering a cell clears its pellet. The existing empty-bank check
and WON session state provide victory without a counter or additional storage.
The green status bar indicates a win. Life loss preserves the bitmap; reset or
restart after game over/win refills it. The initial spawn pellet is collected
once play begins. The renderer shows only remaining pellets.

Compared with held-direction controls alone, the same local SKY130 HD recipe
increased area from 9,235.1072 to 9,580.4384 µm² (+345.3312 µm², +3.74%).
The design still has 153 flip-flops: sharing the bitmap avoids more storage,
but address selection, collection and rendering add combinational logic.
FPGA occupancy increased from 862 to 900 logic cells; the new build passes the
25.2 MHz target with a final nextpnr estimate of 30.44 MHz (seed 10).
These synthesis results do not establish one-tile physical fit; this version
needs a new hardening run and new gate-level validation.

The engine tests and 10,000-frame reference comparison per game passed.
`test/pellets.v` checks all 16 locations, sparse rendering, collection and repeat
visits, non-pellet addresses, enable/pause, victory, life loss, respawn and restart.
The new external-pin `pacman_collectible_pellets` test also passed: a serial
Start+Down report moves the player away, the starting dot disappears from VGA,
an unvisited dot remains and a non-pellet cell stays empty. The earlier full
three-test VGA suite was run on the preceding held-direction version; this
experiment adds this focused pin-level test alongside the engine regressions.

### Remove the idle movement step and expand to 24 pellets

The former `P_INPUT` phase no longer did any work after held-direction controls
removed its direction-memory writes. Its incoming transitions now go directly
to `FINISH`, saving two clocks per affected update while retaining frame-latched
inputs and the session commit protocol. No ghost behaviour or input timeout was
changed. The existing five-bit phase register remains sufficient.

The shared bitmap is now 24 bits. The original 16 pellets retain their locations;
eight new ones occupy columns 2/6/10/14 at rows 5/7. All 24 are reachable from
spawn. Breakout uses only the lower 16 bits, including for victory detection.
Pacman requires all 24 bits to be cleared to win; reset/restart restores them.

| Local SKY130 HD synthesis variant | Cell area (µm²) | Flip-flops |
| --- | ---: | ---: |
| Previous 16 pellets | 9,580.4384 | 153 |
| Remove unused phase, retain 16 pellets | 9,391.5072 | 153 |
| Remove unused phase, expand to 24 pellets | 9,770.6208 | 161 |

The cleanup saves 188.9312 µm²; the expansion adds 379.1136 µm² relative to
that cleaned version. Net growth is 190.1824 µm² (1.99%) over the previous
16-pellet implementation. Physical one-tile fit still requires hardening.
The FPGA build uses 912 logic cells and meets 25.2 MHz (final nextpnr estimate
29.17 MHz, seed 10).

The 24-pellet tests pass collection/rendering of every dot, repeated visits,
non-pellet addresses, pause, no victory after only the first 16 are eaten,
final victory, life preservation and restart. The engine unit tests and
10,000-frame reference comparisons for each game also pass. The Breakout final
brick test explicitly leaves the upper eight bits set to check mode isolation.
The focused external-pin VGA/gamepad test also passed, including display of a
pellet in the new upper bank. The 24-pellet bitstream was copied to the demo
board, its SHA256 verified, and Pacman started with the game-selection helper
restored. The previous 16-pellet bitstream is backed up locally in
`build/pacman24/previous.bin`.


### Remove mouth animation

Removed the animation flip-flop, its updates and the renderer's mouth cut-out.
Pacman is now a solid yellow 8-by-8 logical-pixel square. Local SKY130 HD
synthesis decreases from 9,770.6208 to 9,735.5872 µm² (35.0336 µm² saved),
with 160 rather than 161 flip-flops. FPGA occupancy is 905 logic cells;
nextpnr's final timing estimate is 29.69 MHz, passing the 25.2 MHz target.
Engine/unit tests, all 24 pellet cases, the full solid player shape and
10,000-frame reference comparisons per game passed. No new hardening or
full external-pin simulation was run for this small rendering change.

### Thirty-two collectible pellets experiment

Expanded the shared bank to 32 bits, keeping the player solid and the unused
movement phase removed. Pellets now occupy columns 1/2/5/6/9/10/13/14 at rows
1/3/5/7. All 32 are open and reachable. The regular pattern simplifies the
index to coordinate-bit concatenation; each pellet still clears independently.
Breakout uses only bits 15:0 and ignores the upper sixteen for victory.

The same local SKY130 HD synthesis recipe reports 10,119.7056 µm² and 168 FFs,
versus 9,735.5872 µm² and 160 FFs for 24 pellets without mouth animation.
The increase is 384.1184 µm² (3.95%). This estimate does not establish one-tile
physical fit; the revision needs fresh hardening. The FPGA uses 924 logic cells
and passes 25.2 MHz (final nextpnr estimate 30.29 MHz, seed 10).

Directed tests cover all 32 dots and their disappearance, no early victory,
final victory, life preservation, restart, pause and the solid player shape.
These tests, the engine unit tests, 10,000-frame reference comparisons per game,
and the focused external-pin VGA/gamepad pellet test passed. The FPGA bitstream
was uploaded, its SHA256 verified, and Pacman started at 25.2 MHz with the
selection helper restored. The previous bitstream is backed up locally at
`build/pacman32/previous.bin`.

### Ghost wall-oscillation correction

With the player at maze cell (5,1), the previous greedy chase alternated between
(5,3) and (4,3), unable to route around the intervening wall. The ghost now masks
its reverse direction when any other opening is available, retaining reversal
at a dead end. It reuses the stored heading; no new state is needed. The example
now follows (5,3), (4,3), (3,3), (3,2), (3,1), (4,1), (5,1).
This fixes immediate backtracking, not general pathfinding: larger loops may
still occur with local chase rules.

The regression checks going around this wall and dead-end reversal. Unit and
32-pellet tests, plus 10,000-frame reference comparisons per game, pass.
Local SKY130 synthesis reports 10,089.6768 µm² and 168 FFs, versus 10,119.7056
µm² before; mapping changes yield a small net reduction of 30.0288 µm².
FPGA occupancy is 937 logic cells and final timing is 29.51 MHz, passing 25.2 MHz.
A new hardening run is still needed to determine physical one-tile fit.


### Player speed advantage

Pacman now updates every PLAY frame while the ghost retains alternate-frame
updates. Both use the same one-unit step, so player speed is twice ghost speed
(15 versus 7.5 maze cells per second at 60 Hz). On ghost-idle frames, the engine
enters the player's wall-scan/step directly. Held controls, cell-boundary turns,
32 pellets and the ghost anti-reversal rule remain active.

Local SKY130 synthesis reports 10,262.3424 µm² and 168 FFs: +172.6656 µm²
(+1.71%) versus equal speed. No flip-flops were added, but changed sequencing
increases mapped combinational area. FPGA occupancy is 938 logic cells and
final timing is 29.22 MHz, passing the 25.2 MHz target. Physical fit still needs
hardening. Unit and pellet tests pass; the reference model uses the new cadence.
The 10,000-frame reference comparison per game also passed. The new bitstream
was uploaded and its SHA256 verified; Pacman was started with the selector
helper restored. The previous equal-speed build is backed up locally at
`build/pacman-fast/previous.bin`.


### Four power pellets and vulnerable ghost

Four existing pellets (indices 4/7/12/15; columns 1/13, rows 3/7) are enlarged
from 2×2 to 6×6 logical pixels. They retain their individual bitmap bits.
A fresh pickup loads an eight-bit 240-frame timer; another pickup refreshes it.
No retrigger occurs on an already eaten pellet. The ghost becomes cyan and its
local steering prefers increasing distance from the player, permitting reversal
while vulnerable. Walls remain enforced; this is not a full route planner.
Powered contact resets ghost position/heading, preserving lives and pellet state.
Pickup takes priority over contact; expiration restores lethal contact. Reset,
restart and non-PLAY updates clear the timer; disabled updates pause it.

Local SKY130 HD synthesis reports 10,792.8512 µm² and 176 FFs, versus
10,262.3424 µm² and 168 FFs before power pellets (+530.5088 µm², +5.17%).
The eight added flip-flops are the duration timer. FPGA occupancy is 988 logic
cells; final timing is 30.78 MHz, passing 25.2 MHz. One-tile physical fit is
unverified until another hardening run.

The unit/pellet suite tests all four enlarged shapes, pickup/contact priority,
ghost respawn, cyan/red rendering, timer refresh, no repeated pickup, pause,
flee steering including reversal, exact expiry, normal collision after expiry,
reset, all 32 food bits and victory. The 10,000-frame-per-game comparison also
passes against the updated independent model.
The focused package-pin test passed as well: large versus small pellet pixels,
collection through a Start+Down gamepad report, and a cyan ghost observed on VGA.
The bitstream was uploaded and its SHA256 verified; Pacman was started with the
selection helper restored. The previous build is saved locally under
`build/pacman-power/previous.bin`.


### Keep one power pellet

Only index 12 (column 1, row 7) remains a large power pellet. The former three
power pellets are now ordinary food; there are still 32 independently collected
items. The four-second effect, cyan fleeing ghost and ghost capture are unchanged.
Tests verify exactly one enlarged dot and that the three ordinary replacements
do not activate or refresh the timer. Unit and pellet tests pass. The pin-level
test sequence was updated to reach row 7; it was not rerun for this revision.
Local synthesis is 10,736.5472 µm² (56.3040 µm² less), with 176 FFs unchanged.
FPGA occupancy is 1,007 logic cells and final timing is 29.69 MHz, passing 25.2 MHz.
The different FPGA mapping means fewer ASIC cells need not mean fewer FPGA cells.
One-tile physical fit remains unverified.
The 10,000-frame reference comparisons per game also passed. The bitstream was
uploaded, its SHA256 verified, and Pacman started with the helper restored.


### Simpler ghost steering experiment

Removed all ghost-versus-player coordinate comparisons from direction selection.
The ghost chooses left/right/up/down in fixed priority from open non-reversing
options, reversing only when no other opening exists. This rule is independent
of player location and vulnerability; it can follow repeating routes. The power
pellet still makes the ghost cyan and edible for four seconds, but no longer
makes it flee. All 32 food items and the faster player remain.

The identical local SKY130 synthesis recipe reports 10,695.2576 µm² versus
10,736.5472 µm² before: only 41.2896 µm² (0.38%) saved. Flip-flops remain 176.
This small net mapping benefit is insufficient to claim restored one-tile fit.
FPGA occupancy decreases from 1,007 to 970 logic cells; final timing is 28.74 MHz,
passing 25.2 MHz. Unit and pellet tests pass, including corridor progression,
dead-end reversal and unchanged steering while vulnerable.
The 10,000-frame reference comparison per game passed. The FPGA bitstream was
uploaded, SHA256 verified and Pacman started with the selector helper restored.
The previous build is backed up locally in `build/ghost-simple/previous.bin`.


### Restore chasing/fleeing and reduce food to sixteen

Restored the coordinate-based chase/flee rule, including normal anti-reversal
and vulnerable escape reversal. Removed the extra food bank and its columns:
there are now 15 ordinary pellets and one large power pellet (column 1, row 7).
The same 16-bit bitmap is again fully shared with Breakout. Faster player
movement, four-second vulnerability, ghost capture and the solid player remain.

Local SKY130 synthesis is 10,162.2464 µm² and 160 FFs. Compared with the
32-food simple-ghost experiment (10,695.2576 µm², 176 FFs), this saves
533.0112 µm² (4.98%) and 16 FFs. Compared with the preceding intelligent ghost
with 32 food items, it saves 574.3008 µm² (5.35%). The FPGA uses 956 logic cells
and passes 25.2 MHz (final estimate 31.11 MHz, seed 10). One-tile physical fit
still needs a new hardening run.

Unit tests, all 16 pellet/renderer/power cases, and 10,000-frame comparisons for
each game passed. The external-pin test was adjusted for the removed dots but
was not rerun for this revision. The restored flee and wall-detour cases pass.
The bitstream was uploaded, its SHA256 verified and Pacman started with the
selection helper restored.


### Share the power timer with Breakout scratch storage

The power timer now counts 120 alternate-frame ticks in seven bits, using the
existing movement-phase bit. Bits [2:0] reuse `brick_probe[2:0]`, which is not
otherwise used by Pacman; only four dedicated high bits remain. Probe bits
[5:3] retain the ghost heading. Reset clears the low timer bits, while Breakout
still overwrites its complete probe before using it. Both register writes are
kept in a single owner process to avoid conflicting drivers.

Pickup phase gives 239 or 240 frames of protection (3.983–4.000 seconds at
60 Hz). Tests cover both phases, low-bit carry/borrow, expiry/contact priority,
pause, no repeated pickup, pellet collection and game switching. Unit, pellet
and 10,000-frame-per-game reference checks passed. No full pin-level rerun was
performed for this internal storage change.

Local SKY130 area falls from 10,162.2464 to 10,029.6192 µm²: 132.6272 µm²
(1.31%) saved. Flip-flops fall from 160 to 156. FPGA use is 937 logic cells and
final timing is 29.16 MHz (passes 25.2 MHz). One-tile physical fit still requires
fresh hardening; these are local synthesis estimates.

A separate temporary experiment removed both win/lose status rectangles while
retaining the same gameplay FSM. This mapped to 10,054.6432 µm² and 156 FFs,
25.0240 µm² larger than keeping the bars. The bars have no dedicated registers;
whole-design remapping means this difference is not an intrinsic gate-area cost.
The actual design keeps both bars, as their removal provided no measured saving.
The optimized bitstream (with status rectangles retained) was uploaded, its
SHA256 verified, and Pacman started with the selection helper restored.

### Status rectangle shape experiments (not adopted)

Temporary copies of the shared-timer RTL changed only the two status-rectangle
conditions. Sizes below use 320×240 logical pixels; displayed dimensions are
twice as large in each axis. All variants retain 156 FFs.

| Shape / placement | Local SKY130 area (µm²) |
| --- | ---: |
| Current 80×6, maze y=112 and paddle games y=120 | 10,029.6192 |
| 64×8 at x=128, y=120 in all games | 9,950.7936 |
| 64×4 at x=128, y=120 in all games | 10,098.4352 |
| 64×8 at x=128, retaining separate y=112/120 | 10,040.8800 |
| 80×8, common y=120 | 10,144.7296 |

The best measured variant saves 78.8256 µm² (0.79%). Its condition is
`x[8:6] == 3'd2 && y[7:3] == 5'd15`, allowing shared bit-slice comparisons
instead of general bounds tests and separate vertical positions. Results are
whole-design mapping differences; smaller visible shapes do not necessarily
produce smaller mapped circuits. These are synthesis-only experiments, with
no new FPGA timing or physical-fit claim. Source and board retain the original
rectangles pending a decision to adopt a shape change.


### Adopt the 64×8 status rectangle

Adopted the measured best rectangle in both renderers: x=128..191 and
y=120..127 in logical pixels, shared by all three games. Colour remains red
for loss and green for victory. The adopted source is byte-identical to the
measured `aligned_same_y8` experiment: 9,950.7936 µm² and 156 FFs.
The pellet/power/win-rendering test passed after updating its sample position.
FPGA use is 883 logic cells, with final timing of 32.47 MHz (passes 25.2 MHz).
No new physical hardening was run.
The adopted status-rectangle FPGA bitstream was uploaded, its SHA256 verified,
and Pacman started with the selection helper restored.

### Life-display shape experiments (not adopted)

Temporary copies of the 64×8-status-rectangle design changed only the on-screen
life marker expressions. The life counter, gameplay and seven-segment output
were retained. All variants have 156 FFs; sizes use logical rendering pixels.

| Life display | Local SKY130 area (µm²) |
| --- | ---: |
| Current three separated markers, different y per renderer | 9,950.7936 |
| Original markers, common y=0 | 9,990.8320 |
| Original markers, common y=12 | 10,035.8752 |
| Contiguous bar, common y=12, x=32, width 4×lives | 9,895.7408 |
| Aligned spaced markers, common y=12 | 9,978.3200 |
| Two binary-coded lights, common y=12 | 9,928.2720 |

The best measured shape uses `y[7:2] == 3 && x[8:4] == 2 && x[3:2] < lives`:
height four, width 4/8/12 for 1/2/3 lives, blank at zero. It saves 55.0528 µm²
(0.55%) while preserving three lives. Binary lights save less and are less
intuitive. These are synthesis-only experiments, not adopted or uploaded.
Reducing the maximum lives from three to two still requires two counter bits;
four lives would require three bits in a conventional binary counter. No
lives-count changes were implemented or measured in these experiments.


### Adopt contiguous life bar

Adopted the measured compact bar in both renderers: logical (32,12), height 4,
width 4×lives. The source matches the measured compact-bar experiment exactly:
9,895.7408 µm², 156 FFs. The pellet/power/win-rendering regression passes.
FPGA use is 886 logic cells; final timing is 33.21 MHz (passes 25.2 MHz).
Gameplay life count and seven-segment outputs are unchanged. The source and
board now use this version; no new hardening was run.


### Wider contiguous life bar

Doubled the life-bar width to eight logical pixels per life, retaining logical
origin (32,12) and height four. Full lives now display a 24×4 logical-pixel bar,
or 48×8 VGA pixels. Both renderers use
`y[7:2] == 3 && x[8:5] == 1 && x[4:3] < lives`.
Local SKY130 synthesis is 9,889.4848 µm² and 156 FFs: 6.2560 µm² smaller
than the narrow bar. FPGA use is 883 logic cells and final timing is 32.84 MHz,
passing 25.2 MHz. Gameplay and the seven-segment display are unchanged.
This rendering-only change was checked by synthesis and FPGA implementation;
no new physical hardening was run.


### Shorter gamepad timeout and counter-sharing experiment

Measured the connected PMOD both released and with Right held. Released report
intervals were 981–1001 ms; held Right (0x10) intervals were 980–1001 ms.
A proposed five-bit, frame-rate watchdog would expire around half a second and
interrupt held movement, so it was rejected despite its lower area.

Also prototyped reusing a continuously running version of the existing alternating
frame bit, with a five-bit watchdog at 30 Hz. This mapped to 10,073.4112 µm²
and 154 FFs: 183.9264 µm² larger than the baseline. The 10,000-frame comparison
passed, but a directed power-timer test had a changed pause-phase assumption;
this prototype was not adopted or loaded. Neither its global phase change nor
its altered pause cadence is present in the actual design.

Adopted a six-bit age counter saturating at 62. Reports reset it to zero; stale
buttons clear on the 63rd frame update, giving roughly 1.03–1.05 seconds.
This accommodates the measured one-second reports without changing game cadence.
Local synthesis remains exactly 9,889.4848 µm², but FFs decrease from 156 to 155;
other mapped logic offsets the FF footprint saving. FPGA use decreases to 860
logic cells and final timing is 33.67 MHz (passes 25.2 MHz).

New unit checks retain held input through repeated 60-frame report intervals,
check the 62/63-frame boundary, saturation, recovery after timeout, and immediate
release on the disconnected-controller marker. The full unit suite passed.
The power effect, gameplay and rendering logic were not changed.


### Brick visibility mask experiment (2026-10-03)

Tested moving the Pong brick-visibility condition from the 16-bit brick bank
before selection to the selected brick bit inside the shared renderer.
A Yosys SAT proof verified identical RGB output for every renderer input
combination, with the original renderer receiving the masked bank.

Using the same local SKY130 HD synthesis recipe on the complete three-game
core, the unchanged baseline measured 9,889.4848 square micrometers and 155
flip-flops; the candidate measured 10,037.1264 square micrometers and 155
flip-flops. The candidate increased area by 147.6416 square micrometers
(1.49%), so it was not adopted. Equivalent Boolean expressions can lead to
different optimization and cell-mapping results. These are synthesis areas,
not routed occupancy measurements. No FPGA reprogramming was needed.

Experiment sources, synthesis logs, and the equivalence proof are retained
in `build/brick-mask-experiment/` (local build artifacts).


### Shared overlays and power-timer experiments (2026-10-03)

Tested against commit `5508f8c`, with the identical local SKY130 HD synthesis
recipe on the complete three-game design. The overlay variant moves the life
bar and win/lose rectangle after game RGB selection. Renderer parameters disable
the original overlays in the top-level build while retaining them by default
for standalone renderer tests. Constant parameters do not add hardware.
A SAT proof verified identical final RGB for all renderer input combinations,
including every mode, state, life count, coordinate, and active-video value.

The first timer variant loads 127 instead of 120 at the existing 30 Hz cadence,
giving 253–254 subsequent frames (about 4.22–4.23 seconds) of protection.
Additional synthesis-only screening tried a seven-bit up-counter and eight-bit
up/down counters with the MSB marking the active interval. The eight-bit versions
would provide 128 ticks (about 4.25–4.27 seconds) and add one FF. These additional
encodings were not subjected to gameplay regressions because none saved area.

| Variant | Local cell area (µm²) | FFs |
| --- | ---: | ---: |
| Baseline | 9,889.4848 | 155 |
| Shared final overlays | 10,127.2128 | 155 |
| 127-tick down-counter | 10,019.6096 | 155 |
| Shared overlays + 127-tick down-counter | 10,004.5952 | 155 |
| 127-tick up-counter | 9,975.8176 | 155 |
| Shared overlays + 127-tick up-counter | 10,069.6576 | 155 |
| 128-tick up-counter, MSB active | 9,985.8272 | 156 |
| Shared overlays + 128-tick up-counter | 10,104.6912 | 156 |
| 128-tick down-counter, MSB active | 10,063.4016 | 156 |
| Shared overlays + 128-tick down-counter | 10,122.2080 | 156 |

The combined shared-overlay/127-tick down-counter candidate passed control and
engine unit tests, directed pellet/power tests (including both pickup phases,
expiration collision, pause, and restart), and the 10,000-frame comparison for
each game with the reference timer adjusted to 127 ticks. The SAT proof covers
the composed video path; standalone renderer tests retain their default overlays.
No FPGA build, upload, or hardening was performed for these larger candidates.

All candidates increased mapped area, so neither proposal was adopted. The
working RTL and FPGA image remain unchanged. Sources, synthesis logs, proof,
and modified experimental tests are in `build/overlay-timer-experiment/` as
local build artifacts. Synthesis savings cannot be inferred merely from simpler
source expressions or visually duplicated logic.


### Replace timed vulnerability with ghost teleport (2026-10-03)

The large pellet at maze column 1, row 7 now immediately returns the ghost to
its starting location (column 14, row 10), facing left, regardless of its current
position. Pickup takes priority over same-update contact. The ghost stays red
and resumes its existing intelligent, anti-reversal chase on subsequent ghost
updates. There is no lasting immunity or edible-ghost/fleeing mode. The other
15 pellets and collect-all victory are unchanged; life loss preserves cleared
food and restart restores the bank.

Removed the four dedicated power-timer FFs, updates to the three shared timer
bits, countdown/expiry logic, fleeing selection and frightened colour/interface.
The existing ghost coordinates and heading handle teleportation without new
state. Local SKY130 HD area is 9,626.7328 µm² with 151 FFs, down from
9,889.4848 µm² and 155 FFs: 262.7520 µm² (2.66%) and four FFs saved.
This remains 374.1088 µm² above the 9,252.6240 µm² previously hardened local
baseline; new hardening is required to establish physical fit.

Directed tests passed for remote pickup on both movement phases, disabled
engine, same-update contact, no repeat teleport, red ghost, resumed chase,
ordinary pellets, immediate later collision, last-pellet victory, life loss,
and restart. Control/engine unit tests and the 10,000-frame reference comparison
for each game passed. FPGA implementation uses 839/5,280 LCs and meets 25.2 MHz
(final nextpnr estimate 33.31 MHz).

The bitstream was uploaded to the demo board, SHA256 verified, and Pacman
started at exactly 25.2 MHz with the game-selection helper restored. All INPUT
DIPs read OFF before loading and the Pico BIDIR output enable remains zero.
Uploaded SHA256: `99e2d993d83fc639f35d41a8e524666da20754c9d8f6cd1dacd8968178d4b470`.
The focused external-pin VGA/gamepad pellet regression passed. Its movement
sequence was extended from 26 to 30 frames so Pacman's yellow square leaves the
power-pellet cell before checking that the pellet disappears; the earlier sample
was obscured by the player. The test also checks that the ghost stays red.
Experiment sources and logs are retained in `build/pacman-teleport/`.
