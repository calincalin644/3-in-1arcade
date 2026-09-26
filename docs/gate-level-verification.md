# Extended gate-level verification

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
submission archive exactly matches the current source. The actual routed
netlist was used without modification.

Archive SHA256: `a682550dffe4402ff499209211c5422b15fd6bd8b955436f6d725505927311f7`.

Local simulation used Icarus Verilog 12.0 and cocotb 2.1.0, with the original
upstream SKY130 HD functional cell models, connected power pins and unit delays.
No SPEF/SDF parasitic timing was back-annotated. This establishes passing
functional test cases; it does not resolve the separate maximum-slew warnings
or constitute exhaustive equivalence of the entire design.

The existing GitHub test and gate-level workflows discover all three cocotb
cases automatically. Run `make test` for local RTL/reference testing. With the
Tiny Tapeout PDK available and the artifact netlist copied to
`test/gate_level_netlist.v`, use `make -C test GATES=yes PDK_ROOT=...` for all
external-pin gate-level cases. The local study's logs, result XML and exact
model/archive hashes are retained in `breakout/build/gl-coverage/` in the
working workspace.

No RTL, hardening settings, FPGA bitstream or board programming changed.
