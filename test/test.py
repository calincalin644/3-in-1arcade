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
    assert int(dut.uo_out.value) == 0x4f  # Three lives, decimal point off.

    # Known initial image: row colors, brick gaps, paddle, ball, life indicators.
    samples = [(72, 24, {(3, 3, 3)}), (584, 24, {(0, 0, 0)}),
               (100, 40, {(0, 0, 0)}),
               (70, 66, {(3, 0, 1)}), (70, 82, {(3, 2, 0)}),
               (70, 98, {(1, 3, 0)}), (70, 114, {(0, 2, 3)}),
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
