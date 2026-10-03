"""ETR software controls: BOOT, live DIP selection and gamepad shortcuts.
ASIC RTL is unchanged. All active input drives are HIGH; no DIP is driven LOW.
"""
import machine
import rp2
import time

_controller = None
MODES = {0: 'Breakout', 1: 'Pong', 3: 'Pacman'}

def shortcut(bits):
    if bits == 0xfff or not (bits & 0x200):  # disconnected or Select released
        return None
    choice = bits & 0xc08  # B, Y, A: require exactly one
    return {0x800: 0, 0x400: 1, 0x008: 3}.get(choice)

class BootArcade:
    def __init__(self, board):
        from arcade_gamepad import GamepadReader
        self.board = board
        self.timer = machine.Timer(-1)
        self.loaded = False
        self.busy = False
        self.pulsing = False
        self.release_at = 0
        self.previous_sample = 0
        self.stable_button = 0
        self.presses = 0
        self.switches = 0
        self.read_button = rp2.bootsel_button
        self.loader_globals = None
        self.mode_override = None
        self.last_shortcut = None
        self.pad_buttons = 0
        self.pad_seen_at = time.ticks_ms()
        self.reader = GamepadReader(board)
        self.dip_candidate = self.read_dips()
        self.dip_stable = self.dip_candidate
        self.dip_since = time.ticks_ms()
        self.timer.init(period=20, mode=machine.Timer.PERIODIC, callback=self.poll)

    def is_arcade(self):
        selected = self.board.shuttle.enabled
        return selected is not None and selected.name == 'tt_um_breakout'

    def mode_pins(self):
        return (self.board.pins.ui_in3.raw_pin, self.board.pins.ui_in7.raw_pin)

    def drive_mode(self):
        for i, pin in enumerate(self.mode_pins()):
            if self.mode_override is not None and (self.mode_override & (1 << i)):
                pin.init(machine.Pin.OUT, value=1)
            else:
                pin.init(machine.Pin.IN, pull=machine.Pin.PULL_DOWN)

    def read_dips(self):
        pins = self.mode_pins()
        for pin in pins:
            pin.init(machine.Pin.IN, pull=machine.Pin.PULL_DOWN)
        time.sleep_us(200)
        value = pins[0].value() | (pins[1].value() << 1)
        if self.mode_override is not None and self.is_arcade():
            self.drive_mode()
        return value

    def release(self):
        if self.pulsing:
            self.board.pins.ui_in2.raw_pin.init(machine.Pin.IN, pull=machine.Pin.PULL_DOWN)
            self.pulsing = False

    def launch(self):
        self.board.pins.ui_in2.raw_pin.init(machine.Pin.OUT, value=1)
        self.pulsing = True
        self.release_at = time.ticks_add(time.ticks_ms(), 140)

    def ensure_loaded(self):
        from ttboard.mode import RPMode
        if not self.is_arcade():
            self.release()
            self.mode_override = None
            self.drive_mode()
            namespace = {'__name__': 'arcade_run'}
            with open('/arcade_run.py') as source:
                exec(source.read(), namespace)
            self.loader_globals = namespace
            self.board = namespace['tt']
            time.sleep_ms(100)
        if self.board.mode != RPMode.ASIC_MANUAL_INPUTS:
            raise RuntimeError('Arcade controls require manual input mode')
        self.loaded = True

    def select_game(self, mode, source='gamepad'):
        if mode not in MODES:
            return False
        dips = self.read_dips()
        if source == 'gamepad' and dips != 0:
            print('Gamepad selection: set DIP 3 and 7 OFF first.')
            return False
        if source == 'dip' and dips != mode:
            return False
        self.ensure_loaded()
        self.release()
        self.board.reset_project(True)
        try:
            self.mode_override = mode if source == 'gamepad' else None
            self.drive_mode()
            time.sleep_ms(10)
        finally:
            self.board.reset_project(False)
        time.sleep_ms(100)
        # Leave the complete brick field visible until an explicit serve.
        if mode != 0:
            self.launch()
        self.switches += 1
        print('Arcade selection:', MODES[mode], 'via', source)
        return True

    def handle_pad(self, bits):
        self.pad_buttons = bits
        self.pad_seen_at = time.ticks_ms()
        requested = shortcut(bits)
        previous = self.last_shortcut
        self.last_shortcut = requested
        if requested is not None and requested != previous:
            self.select_game(requested, 'gamepad')

    def handle_dips(self, value, now):
        if value != self.dip_candidate:
            self.dip_candidate = value
            self.dip_since = now
        elif value != self.dip_stable and time.ticks_diff(now, self.dip_since) >= 500:
            self.dip_stable = value
            if self.is_arcade() and value in MODES:
                self.select_game(value, 'dip')

    def press(self):
        self.ensure_loaded()
        self.launch()
        self.presses += 1
        print('Arcade BOOT: launch', self.presses)

    def poll(self, _timer):
        if self.busy:
            return
        self.busy = True
        try:
            now = time.ticks_ms()
            if self.pulsing and time.ticks_diff(now, self.release_at) >= 0:
                self.release()
            if not self.is_arcade() and self.mode_override is not None:
                self.mode_override = None
                self.drive_mode()
            self.handle_dips(self.read_dips(), now)
            while self.reader.sm.rx_fifo():
                bits = self.reader.read()
                if bits is not None:
                    self.handle_pad(bits)
            if time.ticks_diff(now, self.pad_seen_at) > 2200:
                self.last_shortcut = None
            sample = int(bool(self.read_button()))
            if sample == self.previous_sample and sample != self.stable_button:
                self.stable_button = sample
                if sample:
                    self.press()
            self.previous_sample = sample
        except Exception as exc:
            self.release()
            print('Arcade control error:', exc)
        finally:
            self.busy = False

    def stop(self):
        self.timer.deinit()
        self.reader.stop()
        self.release()
        self.mode_override = None
        self.drive_mode()


def install(board):
    global _controller
    if _controller is not None:
        _controller.stop()
    _controller = BootArcade(board)
    print('Arcade controls: BOOT or Select+B/Y/A; gamepad selection needs DIP 3/7 OFF.')
    return _controller
