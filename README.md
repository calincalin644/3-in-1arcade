# Tiny Arcade: Breakout, Pong & Pacman

Three games in Verilog for the **Tiny Tapeout ETR/FabricFox FPGA kit**, targeting
**SKY 26d / SKY130, one tile**. Shared video and game logic generate 640×480 VGA
at 60 Hz with RGB222 (64 colors), without a framebuffer. The onboard 7-segment
display shows lives as horizontal bars: bottom for one, bottom + middle for two,
and all three for three; zero is blank.

| Breakout | Pong | Pacman-style maze |
| :---: | :---: | :---: |
| ![Breakout with 16 bricks](docs/preview.png) | ![Pong with player and CPU paddles](docs/pong.png) | ![Pacman maze with player and ghost](docs/pacman.png) |

*Screenshots captured from the current RTL's simulated VGA output.*

## Connect and play

- **BIDIR:** Tiny VGA PMOD and monitor.
- **INPUT:** optional Psychogenic Gamepad PMOD (controller 1), or use DIP switches.
- Use **ASIC_MANUAL_INPUTS** mode and a **25.2 MHz** clock; the FPGA loader sets both.
- With a gamepad connected, leave DIP **4/5/6 OFF** (latch/clock/data).

Select the game, then **reset**. Switch labels are zero-based:

| Game | DIP 3 | DIP 7 |
| --- | --- | --- |
| Breakout | OFF | OFF |
| Pong | ON | OFF |
| Pacman | ON | ON |

| Action | DIP | Gamepad |
| --- | --- | --- |
| Left / right | 0 / 1 | D-pad left / right |
| Launch / restart | 2, OFF → ON | A or Start |
| Pacman up / down | — | D-pad up / down |

One controller is enough. Release launch before pressing again; after game over,
press once to restart and again to launch. See [wiring and gameplay](docs/info.md)
for custom three-button boards and protocol details.

## Build and test

Requires Yosys, nextpnr-ice40, IceStorm and Icarus Verilog; `mpremote` for upload.
Run from this repository:

```sh
pip install -r test/requirements.txt
pip install mpremote
make                             # FPGA bitstream
make test                        # RTL, reference and VGA tests
make upload PORT=/dev/ttyACM0      # ETR/FabricFox with Tiny Tapeout SDK
```

## ASIC hardening

Push to GitHub to run the SKY 26d workflows. After a successful run, download
`tt_submission` from the GDS workflow's artifacts.

**One-tile fit is still unverified.** The current 16-brick build passes local RTL
and FPGA checks; its local cell-area estimate is about **9,253 µm²**, excluding
physical implementation overhead. Final routing, timing, DRC and LVS must pass.

See [design, area experiments and hardening notes](docs/development.md) for details.
