"""External-pin tests, also suitable for the SKY130 gate-level netlist."""
import cocotb
from cocotb.triggers import Timer

FRAME = 800 * 525


async def cycles(n):
    await Timer(n * 40, unit="ns")


def rgb(value):
    return (((value & 1) * 2 + ((value >> 4) & 1)),
            (((value >> 1) & 1) * 2 + ((value >> 5) & 1)),
            (((value >> 2) & 1) * 2 + ((value >> 6) & 1)))


@cocotb.test()
async def video_and_controls(dut):
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await Timer(210, unit="ns")
    dut.rst_n.value = 1
    # The registered outputs show pixel (0,0) after the first active edge.
    await cycles(1)
    pos = 0

    async def pixel(h, v):
        nonlocal pos
        target = v * 800 + h
        delta = (target - pos) % FRAME
        if delta:
            await cycles(delta)
        pos = target
        return int(dut.uio_out.value)

    # Horizontal and vertical sync boundaries plus blanking on every line.
    for line in range(525):
        for h in (0, 639, 640, 655, 656, 751, 752, 799):
            value = await pixel(h, line)
            assert (value >> 7) == int(not (656 <= h < 752)), (h, line, value)
            assert ((value >> 3) & 1) == int(not (490 <= line < 492)), (h, line, value)
            if h >= 640 or line >= 480:
                assert rgb(value) == (0, 0, 0), (h, line, value)
    assert int(dut.uio_oe.value) == 0xff
    assert int(dut.uo_out.value) == 0x49  # Three horizontal life bars, decimal point off.

    # Known initial image: row colors, brick gaps, paddle, ball, life indicators.
    samples = [(72, 24, {(3, 3, 3)}), (584, 24, {(0, 0, 0)}),
               (100, 40, {(0, 0, 0)}),
               (70, 66, {(3, 0, 1)}), (70, 82, {(3, 0, 1)}),
               (70, 96, {(0, 0, 0)}), (70, 98, {(0, 2, 3)}), (70, 114, {(0, 2, 3)}),
               (64, 66, {(0, 0, 0)}), (300, 442, {(0, 3, 3)}),
               (320, 434, {(3, 3, 3)})]
    for h, v, expected in samples:
        assert rgb(await pixel(h, v)) in expected, (h, v, expected)

    # Hold both directions: paddle remains centered after debounce.
    dut.ui_in.value = 3
    await cycles(5 * FRAME)
    assert rgb(await pixel(290, 442)) == (0, 3, 3)
    # Exercise both directions through external pins. Endpoint clamps and
    # directed collision cases are covered by the faster RTL unit test.
    dut.ui_in.value = 1
    await cycles(8 * FRAME)
    assert rgb(await pixel(270, 442)) == (0, 3, 3)
    assert rgb(await pixel(350, 442)) == (0, 0, 0)
    dut.ui_in.value = 2
    await cycles(12 * FRAME)
    assert rgb(await pixel(350, 442)) == (0, 3, 3)
    # Launch then release: no white ball may remain on the serve row.
    dut.ui_in.value = 4
    await cycles(8 * FRAME)
    for h in range(64, 576, 2):
        assert rgb(await pixel(h, 434)) != (3, 3, 3)
    dut.ui_in.value = 0


class ArcadePins:
    """Drive only package pins; raster position is tracked from reset/clock time."""

    def __init__(self, dut):
        self.dut = dut
        self.selector = 0
        self.pos = 0

    async def reset(self, selector):
        from cocotb.triggers import FallingEdge

        self.selector = selector
        self.dut.ena.value = 1
        self.dut.uio_in.value = 0
        self.dut.ui_in.value = selector
        self.dut.rst_n.value = 0
        await FallingEdge(self.dut.clk)
        await cycles(4)
        self.dut.rst_n.value = 1
        # First active rising edge, plus 10 ns for registered output settling.
        await Timer(30, unit="ns")
        self.pos = 0
        assert int(self.dut.uio_oe.value) == 0xff
        assert int(self.dut.uo_out.value) == 0x49

    async def advance(self, clocks):
        await cycles(clocks)
        self.pos = (self.pos + clocks) % FRAME

    async def frames(self, count):
        await self.advance(count * FRAME)

    async def pixel(self, h, v):
        await self.advance((v * 800 + h - self.pos) % FRAME)
        value = int(self.dut.uio_out.value)
        assert (value >> 7) == int(not (656 <= h < 752)), (h, v, value)
        assert ((value >> 3) & 1) == int(not (490 <= v < 492)), (h, v, value)
        return rgb(value)

    async def packet(self, controller1=0, controller2=0):
        # Psychogenic PMOD reports controller 2 first, controller 1 last.
        # Each 12-bit word: B,Y,Select,Start,Up,Down,Left,Right,A,X,L,R.
        data = (controller2 << 12) | controller1
        for bit in range(23, -1, -1):
            pins = self.selector | (((data >> bit) & 1) << 6)
            self.dut.ui_in.value = pins
            await self.advance(8)
            self.dut.ui_in.value = pins | 0x20
            await self.advance(8)
            self.dut.ui_in.value = pins
            await self.advance(8)
        self.dut.ui_in.value = self.selector | 0x10
        await self.advance(8)
        self.dut.ui_in.value = self.selector
        await self.advance(8)

    async def span(self, y, color):
        matches = []
        for x in range(64, 576, 2):
            if await self.pixel(x, y) == color:
                matches.append(x)
        assert matches, ("No object of expected color", y, color)
        return min(matches), max(matches)

    async def maze_characters(self):
        # Local pixel (4,4) is inside characters but outside even large pellets.
        player, ghost = [], []
        for row in range(1, 11):
            for col in range(1, 15):
                color = await self.pixel(64 + col * 32 + 8,
                                         32 + row * 32 + 8)
                if color == (3, 3, 0):
                    player.append((col, row))
                elif color in ((3, 0, 0), (0, 3, 3)):
                    self.ghost_color = color
                    ghost.append((col, row))
        assert len(player) == 1 and len(ghost) == 1, (player, ghost)
        return player[0], ghost[0]


@cocotb.test()
async def pong_gamepad_and_selection(dut):
    pins = ArcadePins(dut)
    await pins.reset(0x08)
    assert await pins.pixel(260, 42) == (3, 0, 3)  # CPU paddle identifies Pong.
    assert await pins.pixel(100, 70) == (0, 0, 0)  # No Breakout bricks.
    assert await pins.pixel(324, 434) == (3, 3, 3)  # Ball on serve row.
    initial = await pins.span(442, (0, 3, 3))

    # A command from controller 2 alone must not move controller 1's paddle.
    await pins.packet(controller2=1 << 4)
    await pins.frames(3)
    assert await pins.span(442, (0, 3, 3)) == initial

    await pins.packet(controller1=1 << 5)  # Left.
    await pins.frames(4)
    left = await pins.span(442, (0, 3, 3))
    assert left[0] < initial[0], (initial, left)

    await pins.packet(controller1=(1 << 5) | (1 << 4))
    await pins.frames(3)
    assert await pins.span(442, (0, 3, 3)) == left  # Opposing directions stop.

    await pins.packet(controller1=1 << 4)  # Right.
    await pins.frames(6)
    right = await pins.span(442, (0, 3, 3))
    assert right[0] > left[0], (left, right)

    # The disconnected-controller marker releases every button.
    await pins.packet(controller1=0xfff)
    await pins.frames(3)
    assert await pins.span(442, (0, 3, 3)) == right
    cpu = await pins.span(42, (3, 0, 3))
    assert cpu[0] > 256, cpu  # CPU has followed the changed serve position.

    await pins.packet(controller1=1 << 3)  # A launches the rally.
    await pins.frames(2)
    await pins.packet()
    await pins.frames(6)
    for h in range(64, 576, 2):
        assert await pins.pixel(h, 434) != (3, 3, 3), "Ball did not launch"
    # Find the moving ball above its serve row; loss of the ball renderer fails.
    ball_seen = False
    for v in range(354, 434, 8):
        for h in range(66, 576, 8):
            ball_seen |= await pins.pixel(h, v) == (3, 3, 3)
    assert ball_seen, "No moving Pong ball visible"

    # Selector changes take effect only on reset.
    dut.ui_in.value = 0
    await pins.frames(1)
    await pins.span(42, (3, 0, 3))
    await pins.reset(0)
    assert await pins.pixel(260, 42) == (0, 0, 0)
    assert await pins.pixel(70, 66) == (3, 0, 1)
    dut._log.info("Pong: both controllers decoded, movement, release, launch and selection passed")


@cocotb.test()
async def pacman_gamepad_and_walls(dut):
    pins = ArcadePins(dut)
    await pins.reset(0x88)
    assert await pins.pixel(200, 110) == (0, 0, 3)  # Interior maze wall.
    player0, ghost0 = await pins.maze_characters()
    assert player0 == (1, 1) and ghost0 == (14, 10), (player0, ghost0)

    await pins.packet(controller1=(1 << 8) | (1 << 6))  # Start + Down.
    await pins.frames(2)
    await pins.packet(controller1=1 << 6)  # Release Start; keep Down held.
    await pins.frames(20)
    player_down, ghost_down = await pins.maze_characters()
    assert player_down[1] > player0[1], (player0, player_down)
    assert ghost_down != ghost0, (ghost0, ghost_down)
    assert int(dut.uo_out.value) == 0x49

    await pins.packet(controller1=0)  # Releasing the D-pad stops the player.
    await pins.frames(2)
    player_stopped, _ = await pins.maze_characters()
    await pins.frames(8)
    player_released, _ = await pins.maze_characters()
    assert player_released == player_stopped, (player_stopped, player_released)

    await pins.packet(controller1=1 << 7)  # Up reverses at an open junction.
    await pins.frames(20)
    player_up, _ = await pins.maze_characters()
    assert player_up[1] < player_down[1], (player_down, player_up)
    assert player_up[1] == 1, player_up
    # Continue pushing into the top wall: the player must remain inside.
    await pins.frames(8)
    player_wall, _ = await pins.maze_characters()
    assert player_wall[1] == 1, player_wall
    assert await pins.pixel(200, 110) == (0, 0, 3)
    assert int(dut.uo_out.value) == 0x49

    # Reset back to Pong verifies both mode bits across successive resets.
    await pins.reset(0x08)
    assert await pins.pixel(260, 42) == (3, 0, 3)
    assert await pins.pixel(200, 110) == (0, 0, 0)
    dut._log.info("Pacman: maze, player/ghost movement, Start, Up/Down and top wall passed")


@cocotb.test()
async def pacman_collectible_pellets(dut):
    """Follow collection through package inputs and VGA, without internal forcing."""
    pins = ArcadePins(dut)
    await pins.reset(0x88)
    # Pellet at column 5, row 1; no pellet at column 3, row 1.
    assert await pins.pixel(238, 78) == (3, 3, 0)
    assert await pins.pixel(174, 78) == (0, 0, 0)
    assert await pins.pixel(142, 206) == (0, 0, 0)  # Removed extra bank: column 2, row 5.
    assert await pins.pixel(106, 266) == (3, 3, 0)  # Large power pellet, local (5,5).
    assert await pins.pixel(234, 74) == (0, 0, 0)  # Ordinary pellet stays small.
    await pins.packet(controller1=(1 << 8) | (1 << 6))  # Start + Down.
    # Pass through row 7 and leave it: Pacman's yellow square otherwise
    # covers the cleared pellet pixel and makes a disappearance check ambiguous.
    await pins.frames(30)
    await pins.packet(controller1=0)
    # Player has left its starting cell: that pellet has disappeared.
    assert await pins.pixel(110, 78) == (0, 0, 0)
    assert await pins.pixel(238, 78) == (3, 3, 0)
    assert int(dut.uo_out.value) == 0x49
    await pins.maze_characters()
    assert pins.ghost_color == (3, 0, 0), "Ghost must stay red after teleport"
    assert await pins.pixel(106, 266) == (0, 0, 0), "Teleport pellet was not consumed"
    dut._log.info("Pacman: starting pellet eaten, unvisited pellet retained, sparse map rendered")
