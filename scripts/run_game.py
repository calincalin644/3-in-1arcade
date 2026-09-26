"""mpremote run: load FabricFox and generate the VGA pixel clock."""
import time
import machine
from ttboard.boot.demoboard_detect import DemoboardDetect, DemoboardCarrier
from ttboard.demoboard import DemoBoard
from ttboard.mode import RPMode

DemoboardDetect.probe()
if DemoboardDetect.CarrierVersion != DemoboardCarrier.FPGA:
    raise RuntimeError('FabricFox FPGA not detected')
tt = DemoBoard.get()
tt.mode = RPMode.ASIC_MANUAL_INPUTS
tt.clock_project_stop()
tt.uio_oe_pico.value = 0
tt.shuttle.tt_um_breakout.enable()
# Project selection may apply settings; explicitly leave input pins undriven.
tt.mode = RPMode.ASIC_MANUAL_INPUTS
tt.uio_oe_pico.value = 0  # FPGA drives VGA; RP2350 must only read BIDIR.
tt.reset_project(True)
pwm = tt.clock_project_PWM(25_200_000)
# This SDK prefers even divisors and may choose 25.25 MHz. At 126 MHz,
# divide-by-five PWM produces exact 25.2 MHz with a valid 40/60 duty cycle.
if pwm.freq() != 25_200_000:
    machine.freq(126_000_000)
    pwm.freq(25_200_000)
if pwm.freq() != 25_200_000:
    raise RuntimeError('Could not generate the 25.2 MHz VGA clock')
time.sleep_ms(10)
tt.reset_project(False)
print('Breakout/Pong/Pacman running, pixel clock:', pwm.freq(), 'Hz')
print('VGA PMOD: BIDIR. Onboard 7-segment: remaining lives (0-3).')
print('INPUT: DIP 0=left, 1=right, 2=launch, 3/7 select Pong/Pacman.')
print('Gamepad signals use DIP/PMOD inputs 4/5/6 = ui[4]/ui[5]/ui[6].')
