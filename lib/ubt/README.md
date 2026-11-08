# lib/ubt — Bluetooth

The Bluetooth host stack. The plan, versions, phases and decisions are in
[ROADMAP.md](ROADMAP.md).

## State

Phase 1 has started: **HCI over USB and the HCI core**, host-tested against
a simulated USB controller on `lib/usb`'s simulated xHCI controller, and in
the kernel. A standard controller is brought up at boot and said on the
console:

```
USB:   port 1: 1915:521f full, HCI USB (bluetooth)
BT: hci0 up: HCI 5.2, manufacturer 89, address 11:22:33:44:55:66, LE
```

This laptop's MediaTek RZ608 (`0E8D:0608`) is claimed but not brought up:
it runs nothing until MediaTek's firmware patch is loaded, and nothing can
load a file at boot yet (no filesystem is mounted). Its line says so.

## Use

```
ubt_init()                          ; the USB driver registered (before USB starts)
ubt_adapter_count() / ubt_adapter_get(i)
ubt_hci_cmd(adapter, opcode, params, len)   ; EAX = HCI status, return
                                    ; parameters in adapter.wait_buf
ubt_acl_send(adapter, packet, len)  ; one ACL packet out at a time
adapter.event_fn(adapter, event, len)   ; events not answering a command
adapter.acl_fn(adapter, packet, len)    ; ACL packets in, whole
ubt_service()                       ; endpoint recovery (from the USB poll)
```

## Files

| File | What |
|---|---|
| `ubt.inc` | Errors, HCI packet types, opcodes, events, the adapter record |
| `ubt.asm` | The stack as one translation unit (with `lib/usb`) |
| `hci/core.asm` | Commands with credits and a one-second wait, events (Command Complete, Command Status, hardware errors, the rest upward), the bring-up sequence |
| `tr/usb.asm` | HCI over USB: the USB driver (class E0/01/01), commands as class requests, events and ACL put back together from their length fields, ACL out, recovery, removal |
| `kernel.asm` | The kernel glue: registered before USB starts, each adapter's line after its device's, the service from the USB poll |
| `sim/hci_usb.py` | A simulated USB Bluetooth controller (tests only) |

## Tests

`sh lib/ubt/tests/run_tests.sh` — no QEMU.

| Test | Checks | What |
|---|---|---|
| `test_usb_hci.py` | 34 | Bring-up in order, what is read (version, maker, address, LE, features, commands, buffer sizes), event masks, commands as class requests, events in 16-byte pieces, credits, endpoints; unknown commands, Command Status, a command never answered; other events handed up whole, hardware errors, an unexpected Command Complete, an event ending on a packet boundary; ACL out and back in pieces, one at a time, three packets in one transfer, a length no packet has; a stalled event endpoint recovered; bring-up failing with a status and with no answer; BR/EDR only; two adapters; the MediaTek radio left for its firmware; removal with its memory back |
| `test_bt_kernel.py` | 7 | `kernel.asm` with the USB kernel glue (`bkstub.asm`): the device line then the adapter line, the MediaTek line, failure lines, removal, a radio plugged in after boot, recovery from the USB poll |
