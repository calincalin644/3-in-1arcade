# Tiny Breakout + Pong + Pacman

A small Verilog Breakout game for the **Tiny Tapeout ETR/FabricFox FPGA kit**,
also prepared for **SKY130 GitHub Actions hardening with a 1x1 tile target**.

![Simulation of the VGA output](docs/preview.png)

Classic black background, 32 textured bricks, a cyan paddle, a white ball and
three lives. Bricks include mortar seams, edge highlights and a deterministic
rough surface pattern generated from pixel coordinates; there is no texture RAM.
Hold left/right to move at constant speed; opposing directions stop the paddle.
Press launch to serve. After losing a life, release and press launch again.
A red bar means game over; a green bar means you cleared all bricks. Press
launch once to reset an end state and again to launch the new ball.
Set `ui_in[3]` high while reset is asserted to select Pong. Pong uses the same
VGA timing, RGB222 output, input decoder and three-button/gamepad controls; the
lower paddle is the player and the upper paddle is a simple CPU opponent.
Set both `ui_in[3]` and `ui_in[7]` high during reset to select the third game,
a compact Pacman-style maze with pellets, a moving ghost and a controllable
yellow character. Both characters obey the maze walls. The maze is a constant
map and uses no framebuffer.

Breakout and Pong share one ball/paddle engine, including position registers,
movement arithmetic and common collision checks. All three games share one
lives counter and serve/play/game-over controller; only the selected movement
engine advances. Bricks and the Pong CPU remain mode-specific, and Pacman
retains its own maze movement. Textured bricks are retained.

Under the same local SKY130 mapping, sharing reduced cell area from 15,945 to
13,439 square micrometers (15.7%). This is about 75% of a 1x1 tile's gross area,
before physical implementation overhead; 1x1 fit still requires hardening.

The onboard 7-segment display shows the selected game's remaining lives,
from 3 down to 0. VGA uses `uio_out[7:0]` on BIDIR with all eight output
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

The current connected board was programmed and reported a 25,200,000 Hz project
clock. Without a VGA monitor attached, only the FPGA load and clock setup could
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
isolation of inactive engines from the shared session. Cocotb tests
inspect the external pins for sync boundaries on every line, blanking, initial
graphics, opposing directions, movement and launch. They also work on the
gate-level netlist without accessing internal registers. Simulation uses a
40 ns clock for convenience; timing assertions are in pixel clocks, and hardware
is built and run at 25.2 MHz.

`test/render.v` captures an initial frame from the real simulated VGA output pins
to `build/preview.ppm`; `docs/preview.png` is that image, not an artist's mockup.

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

## Verification and limits

- RTL unit tests and external video/control simulation have passed locally.
- FPGA synthesis, placement and routing passed at 25.2 MHz (27.10 MHz reported
  maximum); the design uses 1,368 of 5,280 FPGA logic cells.
- An early SKY130 mapping estimates about 13,439 square micrometers of standard
  cells with all three games. This is a rough synthesis estimate using OpenROAD's SKY130 HD typical
  library, not Tiny Tapeout signoff: it excludes clock-tree and physical overhead.
- **1x1 ASIC fit is a target, not yet verified.** GitHub hardening must establish
  routed area, timing, DRC and LVS before this can be called tapeout-ready.
- Physical VGA display/controller testing is pending; the generated image is
  from simulation. No numeric score, sound, acceleration or framebuffer is included.

The game uses simple frame-based collision rules: the ball's leading vertical
point selects a brick cell; the tiny gaps between drawn bricks are decorative.
Paddle collisions use the current frame's ball center and paddle position.

References: [Tiny Tapeout pinouts](https://tinytapeout.com/specs/pinouts/),
[Psychogenic Gamepad PMOD](https://github.com/psychogenic/gamepad-pmod),
[SKY template](https://github.com/TinyTapeout/ttsky-verilog-template).
