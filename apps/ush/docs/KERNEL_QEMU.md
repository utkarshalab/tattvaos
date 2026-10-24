# Ush kernel/QEMU qualification

Validated on 2026-10-23 using the production boot loader and kernel, QEMU TCG,
`-cpu max`, and 512 MiB RAM. These are emulator results, not hardware certification.

| Guest | Result |
|---|---|
| SeaBIOS, 1 CPU | PASS |
| OVMF, 1 CPU | PASS |
| OVMF, 4 CPUs | PASS |
| OVMF strict-NX, 1 CPU | PASS |

Each run reached the real kernel memory self-test, scheduler and Ush UART prompt.
The serial test exercised cursor insertion/deletion, history recall, Ctrl-C status
130 and command-list short-circuiting. It waited for a real heartbeat with the
cursor in the middle of `echo ac`, required an exact prompt/text/cursor redraw,
then inserted a character and executed the corrected `echo abc` command.

It also covered owned variables, scientific/hex calculator commands, a nested
calculator session, error recovery, return to the shell and shell exit. Fresh
heartbeats were required while waiting and after exit, proving continued scheduler
progress. Host tests cover all 72 three-command truth-table cases for `;`, `&&`,
`||`, whole-line syntax preflight, PTY editing/draft recall, Ctrl-D, and termios
restoration on normal exit and SIGTERM. The native frontend harness injects a
background message mid-edit and verifies exact cursor restoration and execution.

Also passed: ULF/disk integrity, source section hygiene, scheduler assembly checks,
UEFI memory/map/file/ULF/transition/PE32+ checks, host shell/native frontend tests,
and bundle relocation/ownership/invalid-layout rejection tests. The entire broad
boot regression matrix was not rerun for this application integration.

## Persistent UXFS v2 checks

The working volume engine and native IDE backend also passed separate two-boot
persistence runs under SeaBIOS and OVMF (one CPU each). Each run created files,
wrote contents, copied/renamed a file, created an empty file and nested directory,
then renamed the directory subtree while the shell was inside it. A second
independent QEMU process read the same data image and verified both copies and
nested contents, appended data, and the absence of deleted records. The native
file gate exercised head/tail/grep/wc/stat/du/find/hexdump/df and record reuse after
rm/rmdir. Existing-destination and missing-parent errors preserved files.
Both boots also completed the editor/calculator/yield/exit regressions.

The host gate additionally verifies full record capacity, unchanged disk bytes
on preflight failures, directory-move cycle/path-overflow rejection, recovery
from a corrupt newest bank, and actual NASM commit behavior under partial body,
partial header and flush failures. Invalid checksummed namespace metadata is
rejected. See [the volume contract](../../../storage/uxfs/PERSISTENT_VOLUME.md)
for format, limits and the explicit formatting/attachment procedure. This is a
bounded working UXFS v2 path, not qualification of the legacy VFS stubs or their
advanced feature claims.

```sh
make -C boot ush-storage-test
```

## Time and power control

Native callback tests verify integer sleep bounds, nanosecond-to-second uptime,
System V hook alignment, flush-before-power ordering, and cancellation when a
flush fails. The Linux development runner does not install a power callback.

The real power gate passed SeaBIOS/one CPU and OVMF/four CPUs for both actions:

| Action | Required evidence |
|---|---|
| `reboot` | QMP RESET with guest-reset reason, second kernel/prompt, saved file readable |
| `shutdown` | QMP SHUTDOWN with guest-shutdown reason, normal QEMU exit, saved file readable |

Each uses an isolated persistent UXFS image; BIOS tests also require the primary
boot-image hash to remain unchanged. QMP event records are saved beside serial
logs as `qemu-*-power-*.qmp.json`. This tests actual chipset power behavior, without
an ISA debug-exit substitute. The native hook discovers firmware PMBASE using the
locked PCI API on QEMU PIIX4/ICH9; no generic ACPI AML or hardware claim is made.

```sh
make -C boot ush-power-test
```

The ordinary serial gate also checks numeric uptime, exact VT clear output, and
heartbeats during a two-second cooperative sleep. Host tests cover binary text
boundaries and counts, literal grep, exact basename find, hex/ASCII output,
append overflow, empty-directory protections and record reclamation after delete.

## Repeat

From the repository root in WSL/Linux:

```sh
make -C boot img
make -C boot ush-test
```

The QEMU gate writes UART transcripts to `apps/ush/build/qemu-*.log`, with stderr
beside each log. It uses isolated temporary VM directories and terminates its own
QEMU process on success or failure. No VMs are intentionally left running.

## Build contract

The existing kernel is flat NASM; Ush remains a separately assembled native ELF
object to avoid colliding with other subsystem symbols. The bundle helper freezes
that object, determines section sizes and entry offsets with GNU ld, then lets
NASM assign kernel-owned section addresses. A final ld link resolves every shell
relocation at those addresses. The helper checks RX/data/BSS bounds and installs
the initialized bytes in the temporary image before ULF stamping/atomic publish.
BSS is included in the normal kernel memory footprint, not separately allocated.

The BSP-affine console fiber is cooperative, yields on idle UART polls and uses
restart policy NEVER. The existing 16 KiB fiber stack is sufficient for the BSS-
backed shell/calculator path; the standalone calculator command adapter with its
larger temporary stack buffers is not linked into this kernel path.

Heartbeat and console fibers are cooperative and BSP-affine. Paired diagnostic
hooks erase the active input row, print a complete background message, and redraw
the prompt, visible text and cursor. Other background writers must use that API;
fatal diagnostics remain immediate. Raw UART evidence intentionally contains VT
redraw sequences. The editor currently supports printable ASCII/basic VT keys and
a 64-character scrolling viewport intended for terminals at least 72 columns wide.

## Uedit integration

The terminal editor has a separate [2026-10-24 qualification record](../../uedit/QUALIFICATION.md),
including its newer kernel artifact and real editor/reboot-persistence gate.
The artifact below identifies the earlier shell/power gate recorded on this page.

## Shell/power gate artifact

- Kernel file: 9,910,416 bytes
- Executable prefix: 397,312 bytes
- Owned memory footprint: 52,422,208 bytes
- Kernel SHA-256: `ef87977dd34799772a094ef18e21aec25f8fd67bec3a429dd5c43503f447b52c`

The hash identifies this run, not a permanent release artifact. Rebuilds may differ.
