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
make test                        # All games, gamepad and VGA tests
make upload PORT=/dev/ttyACM0      # ETR/FabricFox with Tiny Tapeout SDK
```

## ASIC hardening

**Successfully hardened in a 1×1 SKY130 tile.** [Run 36261694960](https://github.com/calincalin644/3-in-1arcade/actions/runs/36261694960)
completed on 26 September 2026 for commit `299f5d5`: routing, DRC, LVS, antenna,
setup/hold checks, Tiny Tapeout precheck and the gate-level test passed.
Nonfatal maximum-slew warnings remain; see the [hardening notes](docs/development.md#verified-hardening-result).

Download [tt_submission](https://github.com/calincalin644/3-in-1arcade/actions/runs/36261694960/artifacts/10912098425)
from that run for the ASIC files. Pushing changes runs the SKY 26d workflows again.

All three games have passed external-pin gate-level tests; see
[verification coverage](docs/gate-level-verification.md).
See [design and area experiments](docs/development.md) for implementation details.
