"""A simulated AMD GPIO controller for host tests.

Registers live in a dict keyed by offset. Pin registers are at pin * 4.
Bits 28 (interrupt status) and 29 (wake status) are write-1-to-clear; the
summary registers 0x2F8 and 0x2FC have one bit per group of four pins with
a pending, enabled interrupt; bit 29 of the master register (0xFC) is
counted as an end of interrupt and reads back as 0.

A device drives a pin's input with `drive(pin, level)`: an edge pin
latches status on the edge its polarity selects; a level pin latches
status while the active level holds, and latches again after a clear if
the level still holds.
"""

INT_ENABLE, INT_DELIVER, LEVEL_TRIG = 1 << 11, 1 << 12, 1 << 8
PIN_LEVEL, INT_STATUS, WAKE_STATUS = 1 << 16, 1 << 28, 1 << 29
STATUS0, STATUS1, MASTER, EOI = 0x2F8, 0x2FC, 0xFC, 1 << 29


class SimAMD:
    def __init__(self, base, pins=256):
        self.base = base
        self.pins = pins
        self.regs = {}
        self.inputs = [0] * pins
        self.eois = 0
        self.writes = []                # (offset, value) of every write

    def pin_reg(self, pin):
        return self.regs.get(pin * 4, 0)

    def _active(self, pin, level):
        mode = (self.pin_reg(pin) >> 9) & 3
        return level == (0 if mode == 1 else 1)

    def _maybe_latch_level(self, pin):
        r = self.pin_reg(pin)
        if r & LEVEL_TRIG and r & INT_ENABLE and self._active(pin, self.inputs[pin]):
            self.regs[pin * 4] = r | INT_STATUS

    def drive(self, pin, level):
        old = self.inputs[pin]
        self.inputs[pin] = level
        r = self.pin_reg(pin)
        if not r & INT_ENABLE:
            return
        if r & LEVEL_TRIG:
            self._maybe_latch_level(pin)
        elif old != level:
            mode = (r >> 9) & 3
            rising = level == 1
            if mode == 2 or (mode == 0 and rising) or (mode == 1 and not rising):
                self.regs[pin * 4] = r | INT_STATUS

    def read(self, offset):
        if offset in (STATUS0, STATUS1):
            first = 0 if offset == STATUS0 else 128
            v = 0
            for g in range(32):
                for p in range(first + g * 4, first + g * 4 + 4):
                    if p < self.pins:
                        r = self.pin_reg(p)
                        if r & INT_STATUS and r & INT_ENABLE and r & INT_DELIVER:
                            v |= 1 << g
            return v
        if offset < self.pins * 4 and offset % 4 == 0:
            pin = offset // 4
            r = self.pin_reg(pin) & ~PIN_LEVEL
            return r | (PIN_LEVEL if self.inputs[pin] else 0)
        return self.regs.get(offset, 0)

    def write(self, offset, value):
        value &= 0xFFFFFFFF
        self.writes.append((offset, value))
        if offset == MASTER:
            if value & EOI:
                self.eois += 1
            self.regs[offset] = value & ~EOI
            return
        if offset < self.pins * 4 and offset % 4 == 0:
            old = self.pin_reg(offset // 4)
            w1c = value & (INT_STATUS | WAKE_STATUS)
            kept = old & (INT_STATUS | WAKE_STATUS) & ~w1c
            self.regs[offset] = (value & ~(INT_STATUS | WAKE_STATUS | PIN_LEVEL)) | kept
            self._maybe_latch_level(offset // 4)
            return
        self.regs[offset] = value
