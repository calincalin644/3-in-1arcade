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
