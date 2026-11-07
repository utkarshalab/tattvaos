# lib/usb — the USB stack

Host controllers, the USB core and class drivers. The plan, phases and
decisions are in [ROADMAP.md](ROADMAP.md). Storage is deferred.

## State

- **Phase 0, done:** structures (`usb.inc`) and descriptor parsers
  (`core/desc.asm`), fuzzed against a reference parser.
- **Phase 1, host-tested:** xHCI bring-up, rings, commands, root ports
  and enumeration over control transfers, against the software
  controller in `sim/`.
- **In the kernel:** `kernel.asm` finds the xHCI controllers on PCI, maps
  them, starts them, lists their devices on the console and claims
  keyboards and mice; the input fiber polls it. Host-tested, not yet
  booted on hardware.
- **Phase 2, started:** endpoint configuration, interrupt and bulk
  transfers, and USB boot keyboards and mice into `lib/input`
  (`class/hid`), host-tested.

## Use

```
xhci_attach(bar)                    ; RAX = controller, or 0 (EDX = why)
usb_scan(hc)                        ; enumerate every connected root port
usb_device_count() / usb_device_get(i)
usb_get_string(dev, index, out, size)       ; UTF-8
usb_get_descriptor(dev, type, index, lang, buf, len)
xhci_control(hc, slot, setup, buf, len)     ; any control transfer
usb_config_parse(buf, len, &config) ; interfaces, endpoints, associations
xhci_configure_iface(hc, slot, config, index)   ; its endpoints
xhci_submit(hc, xfer)               ; interrupt or bulk; xfer.done(xfer) later
usb_hid_attach(dev)                 ; boot keyboards and mice → lib/input
usb_hid_service()                   ; LEDs, recovery (the input fiber)
```

Enumeration leaves a device addressed but not configured; the driver that
claims it sets the configuration (`usb_hid_attach` does for keyboards and
mice). Policy authorising devices first comes in Phase 9.

## Hooks

`core/hooks.asm`: `usb_alloc_fn` (zeroed memory that devices can reach),
`usb_delay_fn`, `usb_rd32_fn` and `usb_wr32_fn`. Unset, register access
goes straight to memory; the host tests point them at the simulator.

## Files

| File | What |
|---|---|
| `usb.inc` | Errors, descriptor types, requests, speeds, classes, parsed configuration and BOS records, device and transfer records |
| `usb.asm` | The stack as one translation unit (with `lib/input`) |
| `kernel.asm` | The kernel glue: PCI scan by class, BAR sizing and uncached mapping, the page pool, start-up, the console listing, the fiber's poll with devices plugged in later |
| `core/hooks.asm` | Memory, delays, register access |
| `core/desc.asm` | Device, configuration, string (UTF-16 to UTF-8) and BOS descriptors |
| `core/enum.asm` | Enumeration, descriptors and strings from a device, the device list |
| `hcd/xhci/xhci.inc` | xHCI registers, TRBs, completion codes, driver records |
| `hcd/xhci/init.asm` | Firmware hand-off, reset, slots, scratchpads, command and event rings, port protocols |
| `hcd/xhci/ring.asm` | Producer rings with link TRBs, the event ring and its handler |
| `hcd/xhci/cmd.asm` | Commands, Enable Slot, Address Device, Evaluate Context, Configure Endpoint, endpoint recovery |
| `hcd/xhci/port.asm` | Root ports: status, change bits, reset and warm reset |
| `hcd/xhci/xfer.asm` | Control transfers; interrupt and bulk transfers and their completion |
| `class/hid/hid.asm` | USB boot keyboards and mice: claiming, configuration, reports into `lib/input`, LEDs, recovery |
| `sim/xhci_sim.py` | A software xHCI controller (tests only) |
| `sim/devices.py` | Simulated keyboard, mouse, Bluetooth radio, SuperSpeed disk; report queues and HID class requests |

## Tests

`sh lib/usb/tests/run_tests.sh` — no QEMU.

| Test | Checks | What |
|---|---|---|
| `test_desc.py` | 61 | Record layouts; device, configuration (composite, alternate settings, associations, HID, SuperSpeed companions), string and BOS descriptors; malformed input; 20 000 fuzz rounds against a reference parser with guard bytes around every record |
| `test_hid.py` | 29 | Keyboards and mice end to end: claiming (not the radio), configuration and boot requests, endpoint contexts, typing, the mouse, LEDs from the service, stall and babble recovery, removal, a keyboard refusing boot requests; endpoint contexts for SuperSpeed bulk and high-speed interrupt and isochronous endpoints |
| `test_kernel.py` | 20 | `kernel.asm` with PCI, mapping and the console stubbed (`ukstub.asm`): two controllers on functions of one device, a single-function device's other functions skipped, BAR sizing and restore, the command register, uncached page mappings, the console lines, typing and clicking through the poll, devices plugged in, unplugged and plugged back; no controller, an I/O BAR, registers in RAM, a controller that will not start, a 32-bit BAR, no memory |
| `test_xhci.py` | 48 | Bring-up (hand-off, stubborn firmware, a reset that never ends, 64-byte contexts, out of memory); command ring wrap; enumeration at full, high and SuperSpeed; EP0 packet size correction; strings; stalls and recovery; short transfers; ring and event ring wrap; warm reset; removal; timeouts; running out of slots |
