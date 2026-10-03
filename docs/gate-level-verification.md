# Verification status

## Current RTL and FPGA version

The current gameplay includes held-direction Pacman, 16 collectible pellets,
two cyan ghost-teleport pellets, the revised Pong rebound rule, and left/right inputs
without debounce (their synchronizers remain). The board selector leaves
all three games waiting for an explicit launch. The updated helper passes
12 host tests, including releasing the selection chord before resetting.

Current unit/reference/pellet tests pass. All four external-pin RTL tests and
all nine board-helper tests passed before adding the second teleport pellet.
That addition has directed tests and a fresh VGA capture; an external-pin
rerun is pending. The FPGA build meets 25.2 MHz. The faster video tests
use raster-ordered sampling and shorter control journeys; their latest local
runtimes were 116 s (Breakout), 176 s (Pong), 258 s (Pacman movement/walls),
and 215 s (Pacman pellets), run concurrently. Logs and result XML are in the
local `build/faster-tests/` directory.

**The current revision has not been verified against a newly hardened routed
netlist.** Local synthesis is 9,419.0336 µm² with 147 FFs; physical one-tile fit,
post-route checks and gate-level simulation require a fresh hardening run.
The historical results below do not establish those properties for this RTL.

## Earlier hardened revision: `299f5d5`

The routed netlist from successful SKY26d run 36261694960, commit `299f5d5`,
passed the additional Pong and Pacman external-pin tests on 26 September 2026.
The same two tests also passed against the unchanged RTL. The original Breakout
external-pin test had already passed in that GitHub run and remains unchanged.

| Test | RTL | Routed netlist | Checks |
| --- | --- | --- | --- |
| Pong/gamepad/selection | PASS | PASS | CPU/player paddles, controller 1 left/right, ignored controller 2, opposing directions, disconnected-controller release, A launch, visible moving ball, selector held until reset |
| Pacman/gamepad/walls | PASS | PASS | Initial maze and characters, Start launch, player Down/Up movement, ghost movement, top-wall blocking, lives output and reset back to Pong |

These tests access only package pins, including the clock; they neither force
internal states nor depend on internal signal names. The RTL in the downloaded
submission archive matched the source used for those September tests. It does
not match the current source. The actual routed
netlist was used without modification.

Archive SHA256: `a682550dffe4402ff499209211c5422b15fd6bd8b955436f6d725505927311f7`.

Local simulation used Icarus Verilog 12.0 and cocotb 2.1.0, with the original
upstream SKY130 HD functional cell models, connected power pins and unit delays.
No SPEF/SDF parasitic timing was back-annotated. This establishes passing
functional test cases; it does not resolve the separate maximum-slew warnings
or constitute exhaustive equivalence of the entire design.

The existing GitHub test and gate-level workflows discover all four current
cocotb cases automatically. Use a netlist generated from the same RTL revision;
the earlier artifact does not implement the new gameplay. Run `make test` for local RTL/reference testing. With the
Tiny Tapeout PDK available and the artifact netlist copied to
`test/gate_level_netlist.v`, use `make -C test GATES=yes PDK_ROOT=...` for all
external-pin gate-level cases. The local study's logs, result XML and exact
model/archive hashes are retained in `breakout/build/gl-coverage/` in the
working workspace.

The September gate-level verification itself changed no RTL, hardening settings,
FPGA bitstream or board programming. Subsequent gameplay changes are recorded
in [development history](development.md).
