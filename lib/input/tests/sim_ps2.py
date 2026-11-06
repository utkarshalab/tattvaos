"""A simulated PS/2 controller (i8042) with a keyboard on its first port.

It answers the port reads and writes that lib/input makes through its
input_port_in8_fn / input_port_out8_fn hooks.

Keyboard replies are queued at once when `instant` is True (start-up, where
the driver polls). With `instant` False they wait in `pending` until the
test calls `deliver()`, which is how replies arrive while the driver runs
on interrupts.
"""

DATA, STATUS = 0x60, 0x64
OBF, IBF, AUX = 0x01, 0x02, 0x20


class SimPS2:
    def __init__(self, present=True, selftest=0x55, kbd_present=True):
        self.present = present
        self.selftest = selftest
        self.kbd_present = kbd_present
        self.cfg = 0x45                 # firmware default: IRQ 1, translate
        self.out = []                   # (byte, status bits) waiting to be read
        self.want_cfg = False           # next data byte is the configuration
        self.kbd_arg = None             # keyboard command waiting for its argument
        self.kbd_enabled = False
        self.scanset = 2
        self.leds = None
        self.instant = True
        self.pending = []               # replies held back (instant False)
        self.resend_next = 0            # answer the next N bytes with 0xFE
        self.kbd_writes = []            # every byte written to the keyboard
        self.commands = []              # every controller command

    # --- what the driver sees ------------------------------------------------
    def inb(self, port):
        if not self.present:
            return 0xFF
        if port == STATUS:
            if not self.out:
                return 0
            return OBF | self.out[0][1]
        if port == DATA:
            if not self.out:
                return 0
            return self.out.pop(0)[0]
        return 0xFF

    def outb(self, port, value):
        if not self.present:
            return
        value &= 0xFF
        if port == STATUS:
            self.command(value)
        elif port == DATA:
            if self.want_cfg:
                self.want_cfg = False
                self.cfg = value
            else:
                self.keyboard(value)

    # --- controller ------------------------------------------------------------
    def command(self, c):
        self.commands.append(c)
        if c == 0x20:
            self.out.append((self.cfg, 0))
        elif c == 0x60:
            self.want_cfg = True
        elif c == 0xAA:
            self.out.append((self.selftest, 0))
            self.cfg = 0x00             # some controllers forget it here
        elif c == 0xAB:
            self.out.append((0x00 if self.kbd_present else 0x01, 0))

    # --- keyboard -------------------------------------------------------------
    def reply(self, *data):
        for b in data:
            if self.instant:
                self.out.append((b, 0))
            else:
                self.pending.append(b)

    def deliver(self):
        """Move held-back replies into the output buffer."""
        self.out.extend((b, 0) for b in self.pending)
        self.pending = []

    def keyboard(self, b):
        self.kbd_writes.append(b)
        if not self.kbd_present:
            return
        if self.resend_next:
            self.resend_next -= 1
            self.reply(0xFE)
            return
        if self.kbd_arg is not None:
            cmd, self.kbd_arg = self.kbd_arg, None
            if cmd == 0xED:
                self.leds = b
            elif cmd == 0xF0:
                self.scanset = b
            self.reply(0xFA)
            return
        if b == 0xFF:
            self.kbd_enabled = False
            self.reply(0xFA, 0xAA)
        elif b in (0xED, 0xF0):
            self.kbd_arg = b
            self.reply(0xFA)
        elif b == 0xF4:
            self.kbd_enabled = True
            self.reply(0xFA)
        else:
            self.reply(0xFA)

    # --- test helpers ------------------------------------------------------------
    def keys(self, *codes):
        """Bytes the keyboard sends, as if typed."""
        self.out.extend((c, 0) for c in codes)

    def aux(self, *codes):
        self.out.extend((c, AUX) for c in codes)

    def error_byte(self, code):
        self.out.append((code, 0x40))   # timeout bit set
