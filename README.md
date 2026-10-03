# Tiny Arcade: Breakout, Pong & Pacman

Three Verilog games targeting **Tiny Tapeout SKY 26d / SKY130, one tile**, tested
on the **ETR demo board with the FabricFox FPGA ASIC simulator**. Shared logic
produces 640×480 VGA at 60 Hz with RGB222 (64 available colors), without a
framebuffer. A white on-screen bar and the onboard seven-segment display show
remaining lives.

| Breakout | Pong | Pacman-style maze |
| :---: | :---: | :---: |
| ![Breakout with 16 bricks](docs/preview.png) | ![Pong with player and CPU paddles](docs/pong.png) | ![Pacman maze with player and ghost](docs/pacman.png) |

*Earlier simulated screenshots illustrate the games; pellet and lives graphics
have since changed. The gameplay below describes the current version.*

## Connect and play

- Connect the **Tiny VGA PMOD to BIDIR** and a VGA monitor.
- Connect the optional **Psychogenic Gamepad PMOD to INPUT**, using controller
  connector **1**. Leave DIP **4/5/6 OFF** when it is connected.
- The FPGA loader selects manual-input mode and a **25.2 MHz** clock.
- With the installed demo-board helper, leave DIP **3/7 OFF** and use
  **Select+B = Breakout**, **Select+Y = Pong**, **Select+A = Pacman**.
  Release the shortcut before selecting again.
- Selecting **Breakout waits for A, Start or BOOT to serve**. Pong and Pacman
  auto-launch. Selection resets the chosen game and restores three lives.
- Changing DIP 3/7 to a valid setting for 0.5 seconds also selects the game.
  Without the helper, set the DIPs and press reset; then launch manually.

Switch labels are zero-based:

| Game | DIP 3 | DIP 7 |
| --- | --- | --- |
| Breakout | OFF | OFF |
| Pong | ON | OFF |
| Pacman | ON | ON |

| Action | DIP / custom button | Controller 1 |
| --- | --- | --- |
| Left / right | 0 / 1 | D-pad left / right |
| Launch / restart | 2, OFF → ON | A or Start |
| Pacman up / down | — | D-pad up / down |

The installed **BOOT helper** can load and start the arcade from the factory
test; later BOOT presses act as launch/restart. Keep DIP 2 OFF when using it.
After a lost life, launch again. After game over or victory, press once to reset
the game, release, then press again to launch.

## The games

- **Breakout:** clear the 8×2 brick field. Move the paddle while holding a
  direction; holding both stops it. The impact half determines horizontal bounce.
- **Pong:** face a CPU paddle that follows the ball in coarse columns. Its
  rebound rule varies with impact position and column, breaking the old default
  repeating rally. Missing either paddle costs a life.
- **Pacman:** move while a direction is held; turns occur at maze-cell boundaries.
  Pacman moves twice as fast as the chasing ghost. Eat all **16 pellets** to win.
  The one large pellet immediately teleports the ghost to its starting position.
  It stays red and resumes chasing; there is no timed immunity. Pickup protects
  against contact in that update only. Losing a life preserves collected food.

All games start with three lives. On the seven-segment display, one life lights
only the bottom bar, two light bottom + middle, and three light all horizontal
bars. Zero is blank. See [gameplay, wiring and implementation](docs/info.md).

## Build and test

Requires Yosys, nextpnr-ice40, IceStorm and Icarus Verilog; `mpremote` for upload.
Run from this repository:

```sh
pip install -r test/requirements.txt
pip install mpremote
make                             # FPGA bitstream
make test                        # Unit/reference/pellet and four VGA tests
python3 test/test_board_controls.py  # Nine demo-board helper tests
make upload PORT=/dev/ttyACM0      # FPGA upload with Tiny Tapeout SDK
```

The persistent selector uses `scripts/arcade_boot.py` and
`scripts/arcade_gamepad.py`; see [helper installation and behavior](docs/info.md#demo-board-helper).

## Implementation status

| Current combined design | Result |
| --- | ---: |
| Local SKY130 synthesis cell area | **9,424.04 µm²** |
| Flip-flops | **147** |
| FabricFox FPGA logic cells | **827 / 5,280** |
| FPGA timing | **30.95 MHz**, passing 25.2 MHz |
| Current RTL tests | Unit/reference/pellet tests and all four external-pin video tests pass |
| Demo-board helper tests | 9 pass |

**The current version needs a new ASIC hardening run.** Local synthesis area
and FPGA success do not establish physical one-tile fit.

An earlier revision, commit `299f5d5`, successfully hardened in a 1×1 SKY130 tile
on 26 September 2026: [run 36261694960](https://github.com/calincalin644/3-in-1arcade/actions/runs/36261694960).
Routing, DRC, LVS, antenna, setup/hold checks, Tiny Tapeout precheck and functional
gate-level tests passed, with nonfatal maximum-slew warnings remaining.
Its [tt_submission artifact](https://github.com/calincalin644/3-in-1arcade/actions/runs/36261694960/artifacts/10912098425)
contains that earlier design, not today's gameplay updates.

Pushing changes starts the SKY 26d workflows. See [verification scope](docs/gate-level-verification.md)
and [development and area history](docs/development.md).
