# lib/ubt — Bluetooth

The Bluetooth host stack. The plan, versions, phases and decisions are in
[ROADMAP.md](ROADMAP.md).

## State

**ACL links and L2CAP, every mode**, work between two of our stacks over
a virtual radio: basic, Enhanced Retransmission and Streaming on BR/EDR,
LE credit based on LE, enhanced credit based (up to five channels in one
request, reconfiguration) on both, with all of BR/EDR and LE signalling.

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
ubt_hci_async(adapter, opcode, params, len) ; a command, not waited for
ubt_connect(adapter, bdaddr) / ubt_le_connect(adapter, addr, type)
ubt_disconnect(conn, reason)        ; links; adapter.conn_fn says when
l2cap_server(psm, mode, ops, user)  ; incoming channels on a PSM
l2cap_connect(conn, psm, mode, ops, user)   ; → chan; ops.event says open
l2cap_connect_ecred(conn, psm, n, ops, user, chans) ; n enhanced, one request
l2cap_reconfigure(chan, mtu)        ; a larger MTU on an enhanced channel
l2cap_send(chan, sdu, len) / l2cap_disconnect(chan) / l2cap_echo(conn, ...)
adapter.fixed_fn(conn, cid, data, len)      ; ATT, SMP, connectionless
ubt_service()                       ; queued commands, L2CAP timeouts, waiting
                                    ; ACL, endpoint recovery (the USB poll)
```

## Files

| File | What |
|---|---|
| `ubt.inc` | Errors, HCI packet types, opcodes, events, the adapter record |
| `ubt.asm` | The stack as one translation unit (with `lib/usb`) |
| `hci/core.asm` | Commands with credits and a one-second wait, events (Command Complete, Command Status, hardware errors, the rest upward), the bring-up sequence |
| `hci/conn.asm` | ACL links: create, accept, disconnect, link events, fragmentation to the controller's buffers, flow control by completed packets, reassembly into L2CAP frames |
| `l2cap/l2cap.inc` | CIDs, signalling codes, results, options, modes, the channel and server records, the user's operations |
| `l2cap/core.asm` | Frames by CID, the channel and server tables, basic mode, connect, send, disconnect, echo, timeouts; the other modes by their state |
| `l2cap/sig.asm` | Signalling: every BR/EDR command, configuration negotiation (with the retransmission and flow control option), LE Command Reject, Disconnection and Connection Parameter Update; the credit-based commands handed to `credit.asm` |
| `l2cap/ertm.asm` | Enhanced Retransmission and Streaming modes: the control field, CRC-16 FCS, segmentation and reassembly, the window, acknowledgements, retransmission and monitor timers, Reject, Selective Reject, Receiver Not Ready, polls |
| `l2cap/credit.asm` | LE credit-based and enhanced credit-based modes: K-frames, credits given and topped up, the rules a peer must keep, LE and enhanced connection requests, Flow Control Credit, Reconfigure |
| `tr/mem.asm` | An in-memory transport: a controller in code (the tests' virtual radio) |
| `tr/usb.asm` | HCI over USB: the USB driver (class E0/01/01), commands as class requests, events and ACL put back together from their length fields, ACL out, recovery, removal |
| `kernel.asm` | The kernel glue: registered before USB starts, each adapter's line after its device's, the service from the USB poll |
| `sim/hci_usb.py` | A simulated USB Bluetooth controller (tests only) |
| `sim/radio.py` | A virtual radio: controllers for in-memory adapters, linking them to each other (tests only) |

## Tests

`sh lib/ubt/tests/run_tests.sh` — no QEMU.

| Test | Checks | What |
|---|---|---|
| `test_l2cap.py` | 53 | Two stacks over the virtual radio: paging and accepting, roles, Information Requests; a channel opened on both sides, CIDs, MTUs, the Connection and Configuration Requests byte for byte; 900 bytes cut into 27-byte buffers three at a time, data both ways, too long, buffers held and given back; echo; a PSM nobody serves; closing from one side, the link going; a peer gone quiet (timeout); every BR/EDR command answered as it should be by hand (Command Reject, identifier 0, echo, every information type, bad PSM, fixed CID, CID in use, configuration: MTU, too small, unknown option, unknown hint, another mode, malformed, continuation, unknown CID, disconnection); LE: parameter update accepted and applied, rejected, the peripheral asked, unknown commands, BR/EDR signalling on LE; ATT and SMP to the fixed-channel hook; frames that do not add up; every block given back |
| `test_ertm.py` | 41 | ERTM and streaming between two stacks: the RFC option both ways byte for byte, I-frames with good FCS, Receiver Ready, an SDU in a start and an end, the peer's MTU; a deaf peer: the window fills, the poll after 2 s, everything again in order; a lost frame answered with one Reject; by hand: a wrong FCS dropped, duplicates, polls answered with F, Receiver Not Ready and Ready, Selective Reject (one frame, not an acknowledgement), Reject, an acknowledgement of frames never sent closing the channel; MaxTransmit polls then the channel given up; streaming losing one SDU, no acknowledgements; a mode the peer lacks refused unasked; a configuration without RFC answered unacceptable; every block given back |
| `test_credit.py` | 64 | Credit-based channels: basic mode refused on LE; the LE request and answer byte for byte, K-frames with the SDU length, credits used on both sides, 1017 bytes in five K-frames, credits given back at half, the MTU; 25 SDUs waiting for credits, all in order; by hand: an SDU in pieces, an empty SDU, Flow Control Credit, credits for no channel; a peer breaking each rule (beyond MPS, beyond MTU, no length, more than the SDU, no credit, 65535 credits) losing the channel; no SPSM, the other mode, a CID out of range, in use, MTU or MPS under 23; three enhanced channels in one request and answer, data on each; partly refused, six CIDs, MTU under 64, no SPSM; reconfiguration asked and answered, a larger SDU after it, not smaller, not on LE credit based; every refusal result (1-4) and a smaller MPS for one channel; enhanced over BR/EDR, refused to a peer without it, the LE request not understood there; closing; every block given back |
| `test_usb_hci.py` | 34 | Bring-up in order, what is read (version, maker, address, LE, features, commands, buffer sizes), event masks, commands as class requests, events in 16-byte pieces, credits, endpoints; unknown commands, Command Status, a command never answered; other events handed up whole, hardware errors, an unexpected Command Complete, an event ending on a packet boundary; ACL out and back in pieces, one at a time, three packets in one transfer, a length no packet has; a stalled event endpoint recovered; bring-up failing with a status and with no answer; BR/EDR only; two adapters; the MediaTek radio left for its firmware; removal with its memory back |
| `test_bt_kernel.py` | 7 | `kernel.asm` with the USB kernel glue (`bkstub.asm`): the device line then the adapter line, the MediaTek line, failure lines, removal, a radio plugged in after boot, recovery from the USB poll |
