"""Passive ETR gamepad receiver.
PIO adapted from Pat Deegan, Copyright 2025, GPL-3.0:
https://github.com/psychogenic/gamepad-pmod/blob/main/micropython/gamepad_reader.py
"""
import rp2
from machine import Pin

@rp2.asm_pio(in_shiftdir=rp2.PIO.SHIFT_LEFT)
def read_reports():
    mov(isr, null)
    label('poll')
    jmp(pin, 'report')
    mov(x, isr)
    mov(isr, null)
    in_(pins, 1)
    mov(y, isr)
    mov(isr, x)
    jmp(not_y, 'poll')
    mov(x, isr)
    mov(isr, null)
    in_(pins, 2)
    mov(y, isr)
    mov(isr, x)
    set(x, 1)
    jmp(x_not_y, 'one')
    set(x, 0)
    label('one')
    in_(x, 1)
    wait(0, gpio, 22)
    jmp('poll')
    label('report')
    push(noblock)
    wait(0, gpio, 21)
    mov(isr, null)
    jmp('poll')

class GamepadReader:
    def __init__(self, board):
        pins = tuple(getattr(board.pins, 'ui_in%d' % i).gpio_num for i in (4,5,6))
        if pins != (21,22,23):
            raise RuntimeError('Gamepad selector currently supports ETR v3 pinout')
        if any(rp2.StateMachine(i).active() for i in range(4,8)):
            raise RuntimeError('PIO1 is already in use')
        rp2.PIO(1).remove_program()
        self.sm = rp2.StateMachine(6, read_reports, freq=20_000_000,
                                  in_base=Pin(22), jmp_pin=Pin(21))
        self.discard_first = True
        self.sm.active(1)

    def read(self):
        if not self.sm.rx_fifo():
            return None
        word = self.sm.get() & 0xffffff
        if self.discard_first:
            self.discard_first = False
            return None
        return word & 0xfff

    def stop(self):
        self.sm.active(0)
