"""Host tests for software selection; no ASIC or board access."""
import importlib.util
from pathlib import Path
import sys
import types
import unittest

class Pin:
    IN, OUT, PULL_DOWN = 0, 1, 2
    def __init__(self):
        self.external = 0
        self.mode = self.IN
        self.level = 0
    def init(self, mode, pull=None, value=None):
        if mode == self.OUT:
            assert value == 1, 'Input pins must never be actively driven low'
        self.mode = mode
        if value is not None: self.level = value
    def value(self):
        return self.external | (self.level if self.mode == self.OUT else 0)

class Timer:
    PERIODIC = 1
    def __init__(self, *_): pass
    def init(self, **kw): pass
    def deinit(self): pass

class Reader:
    def __init__(self, board): self.sm = types.SimpleNamespace(rx_fifo=lambda: 0)
    def stop(self): pass

clock = [0]
def advance(ms): clock[0] += ms
sys.modules['machine'] = types.SimpleNamespace(Pin=Pin, Timer=Timer)
sys.modules['rp2'] = types.SimpleNamespace(bootsel_button=lambda: 0)
sys.modules['arcade_gamepad'] = types.SimpleNamespace(GamepadReader=Reader)
sys.modules['ttboard.mode'] = types.SimpleNamespace(RPMode=types.SimpleNamespace(ASIC_MANUAL_INPUTS=1))
sys.modules['time'] = types.SimpleNamespace(ticks_ms=lambda: clock[0],
    ticks_add=lambda a,b:a+b, ticks_diff=lambda a,b:a-b,
    sleep_ms=advance,sleep_us=lambda us:None)
path = Path(__file__).resolve().parents[1]/'scripts/arcade_boot.py'
spec=importlib.util.spec_from_file_location('board_controls',path)
mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)

class Board:
    def __init__(self):
        self.pins=types.SimpleNamespace(**{'ui_in%d'%i:types.SimpleNamespace(raw_pin=Pin()) for i in (2,3,7)})
        self.mode=1
        self.shuttle=types.SimpleNamespace(enabled=types.SimpleNamespace(name='tt_um_breakout'))
        self.resets=[]
    def reset_project(self, active):
        self.resets.append(active)
        if not active:
            self.captured_mode=self.pins.ui_in3.raw_pin.value() | (self.pins.ui_in7.raw_pin.value()<<1)

class ControlsTest(unittest.TestCase):
    def setUp(self):
        clock[0]=0
        self.board=Board();self.ctl=mod.BootArcade(self.board)
    def test_shortcuts(self):
        self.assertEqual([mod.shortcut(x) for x in (0xa00,0x600,0x208)],[0,1,3])
        for bits in (0,0xfff,0x800,0x200,0xe00,0xa08): self.assertIsNone(mod.shortcut(bits))
    def test_mode_latched_reset_and_release(self):
        for mode in (0,1,3):
            self.assertTrue(self.ctl.select_game(mode))
            self.assertEqual(self.board.captured_mode,mode)
            self.assertEqual(self.board.resets[-2:],[True,False])
            self.assertEqual(self.ctl.read_dips(),0)
            self.assertEqual(self.ctl.pulsing, mode != 0)
            advance(141);self.ctl.poll(None)
            self.assertEqual(self.board.pins.ui_in2.raw_pin.mode,Pin.IN)
    def test_breakout_waits_then_boot_launches(self):
        self.ctl.select_game(0)
        self.assertFalse(self.ctl.pulsing)
        self.assertEqual(self.board.pins.ui_in2.raw_pin.mode,Pin.IN)
        self.ctl.press()
        self.assertTrue(self.ctl.pulsing)
    def test_dip_breakout_waits(self):
        self.ctl.select_game(0,'dip')
        self.assertFalse(self.ctl.pulsing)
    def test_active_dip_blocks_gamepad(self):
        self.board.pins.ui_in7.raw_pin.external=1
        self.assertFalse(self.ctl.select_game(0))
        self.assertEqual(self.board.resets,[])
    def test_held_chord_only_switches_once(self):
        self.ctl.handle_pad(0x600);self.ctl.handle_pad(0x600)
        self.assertEqual(self.ctl.switches,1)
        self.ctl.handle_pad(0);self.ctl.handle_pad(0x600)
        self.assertEqual(self.ctl.switches,2)
    def test_stable_dip_switch(self):
        self.board.pins.ui_in3.raw_pin.external=1
        self.ctl.handle_dips(1,0);self.ctl.handle_dips(1,499)
        self.assertEqual(self.board.resets,[])
        self.ctl.handle_dips(1,500)
        self.assertEqual(self.board.captured_mode,1)
        self.assertIsNone(self.ctl.mode_override)
    def test_unchanged_dips_do_not_override_gamepad(self):
        self.ctl.select_game(3)
        for now in (0,500,1000):self.ctl.handle_dips(0,now)
        self.assertEqual(self.ctl.mode_override,3)
        self.assertEqual(self.ctl.switches,1)
    def test_stop_releases_pins(self):
        self.ctl.select_game(3);self.ctl.stop()
        for i in (2,3,7):self.assertEqual(getattr(self.board.pins,'ui_in%d'%i).raw_pin.mode,Pin.IN)

if __name__=='__main__':unittest.main()
