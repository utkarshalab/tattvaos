"""A simulated DesignWare I2C controller with devices on its bus.

Commands written to DATA_CMD run at once against the device at TAR: the
first command starts a transfer (no device: the address is not
acknowledged), RESTART starts a new message, STOP ends the transfer.
After an abort, commands are dropped until the abort is cleared, as the
hardware flushes its FIFO.
"""

CON, TAR, DATA_CMD = 0x00, 0x04, 0x10
SS_HCNT, SS_LCNT, FS_HCNT, FS_LCNT = 0x14, 0x18, 0x1C, 0x20
INTR_MASK, RAW_INTR, CLR_INTR, CLR_TX_ABRT, CLR_STOP_DET = 0x30, 0x34, 0x40, 0x54, 0x60
ENABLE, STATUS, SDA_HOLD, ABRT_SOURCE, ENABLE_STATUS = 0x6C, 0x70, 0x7C, 0x80, 0x9C
COMP_PARAM_1, COMP_TYPE = 0xF4, 0xFC
TX_ABRT, STOP_DET = 1 << 6, 1 << 9
READ, STOP, RESTART = 1 << 8, 1 << 9, 1 << 10


class RegDevice:
    """Registers addressed by the first `width` bytes written (little
    endian); further writes store, reads return from the register on."""

    def __init__(self, data=None, width=1, nack_after=None):
        self.mem = dict(enumerate(data or []))
        self.width = width
        self.nack_after = nack_after    # refuse the Nth data byte written
        self.log = []

    def start(self):
        self.addr_bytes = []
        self.written = 0
        self.log.append("start")

    def restart(self):
        self.log.append("restart")
        self.addr_bytes = self.addr_bytes if len(self.addr_bytes) == self.width else []

    def stop(self):
        self.log.append("stop")

    def write(self, b):
        self.written += 1
        if self.nack_after is not None and self.written > self.nack_after:
            return False
        if len(self.addr_bytes) < self.width:
            self.addr_bytes.append(b)
            if len(self.addr_bytes) == self.width:
                self.ptr = sum(x << (8 * i) for i, x in enumerate(self.addr_bytes))
        else:
            self.mem[self.ptr] = b
            self.ptr += 1
        self.log.append(("w", b))
        return True

    def read(self):
        v = self.mem.get(getattr(self, "ptr", 0), 0xFF)
        self.ptr = getattr(self, "ptr", 0) + 1
        self.log.append("r")
        return v


class SimDW:
    def __init__(self, comp_type=0x44570140):
        self.regs = {COMP_TYPE: comp_type, COMP_PARAM_1: 0x001F1F00}
        self.devices = {}
        self.rx = []
        self.raw = 0
        self.abort_source = 0
        self.aborted = False
        self.active = None
        self.enabled = 0
        self.stuck_busy = False
        self.stuck_enabled = False
        self.fifo_full = False
        self.cmds = []                  # every DATA_CMD write

    def read(self, off):
        if off == DATA_CMD:
            return self.rx.pop(0) if self.rx else 0
        if off == STATUS:
            v = 0 if self.fifo_full else (1 << 1)
            if self.rx:
                v |= 1 << 3
            if self.active is not None or self.stuck_busy:
                v |= 1 << 5 | 1
            return v
        if off == RAW_INTR:
            return self.raw
        if off == CLR_INTR:
            self.raw = 0
            return 0
        if off == CLR_TX_ABRT:
            self.raw &= ~TX_ABRT
            self.abort_source = 0
            self.aborted = False
            return 0
        if off == CLR_STOP_DET:
            self.raw &= ~STOP_DET
            return 0
        if off == ABRT_SOURCE:
            return self.abort_source
        if off == ENABLE_STATUS:
            return 1 if (self.enabled or self.stuck_enabled) else 0
        return self.regs.get(off, 0)

    def _abort(self, source):
        self.raw |= TX_ABRT | STOP_DET
        self.abort_source = source
        self.aborted = True
        if self.active is not None:
            self.active.stop()
        self.active = None

    def write(self, off, v):
        if off == ENABLE:
            self.enabled = v & 1
            if not self.enabled:
                self.rx = []
            return
        if off != DATA_CMD:
            self.regs[off] = v
            return
        self.cmds.append(v)
        if self.aborted or not self.enabled:
            return
        tar = self.regs.get(TAR, 0)
        if self.active is None:
            dev = self.devices.get(tar & 0x3FF)
            if dev is None:
                self._abort(2 if tar & (1 << 12) else 1)
                return
            self.active = dev
            dev.start()
        elif v & RESTART:
            self.active.restart()
        if v & READ:
            self.rx.append(self.active.read())
        elif not self.active.write(v & 0xFF):
            self._abort(1 << 3)        # data not acknowledged
            return
        if v & STOP:
            self.active.stop()
            self.active = None
            self.raw |= STOP_DET
