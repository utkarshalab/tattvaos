; =============================================================================
; Utkarsha OS — kernel/entry.asm
; =============================================================================
; Top-level kernel entry file. Sets up the ULF (Unikernel Loader Format) header
; and includes modular files for startup, early initialization, and main loop.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef KERNEL_ENTRY_ASM
%define KERNEL_ENTRY_ASM

[BITS 64]
[ORG 0x100000]

%include "boot/boot_info.inc"

; -----------------------------------------------------------------------------
; ULF v2 Header (40 bytes)
; -----------------------------------------------------------------------------
ulf_header:
    dd 0x00464C55                   ; magic: "ULF\0"
    ; This size is WRONG as assembled and is overwritten by boot/Makefile.
    ; kernel_end sits in .text, but .data and .rodata are emitted after it in a
    ; flat binary, so the label measures the text extent only — it reported a
    ; 9.3 MiB image as 274 KB. The assembler cannot see past its own section,
    ; so the true length is patched in after the link.
    dd kernel_end - ulf_header      ; size of binary (patched post-link)
    dq kernel_entry                 ; dynamic entry point
    ; The build stamps the additive checksum after patching the final image
    ; size. Stage2 recomputes it across the complete loaded image before any
    ; kernel code executes; this recognizable value is only a build placeholder.
    dq 0x123456789ABCDEF0           ; checksum placeholder
    ; Executable bytes start at the image base and end on a 4KB boundary after
    ; .text. Stage2 uses this independently of the full file size to build an
    ; RX-code/RW+NX-data bootstrap map. Keep it within the first 1MB kernel
    ; window until the boot mapper grows additional 4KB page tables.
    dd kernel_end - ulf_header      ; executable extent in bytes
    dd 2                            ; ULF header version
    ; Exact byte extent of the complete in-memory image, including .bss.
    ; Loaders page-round this value for ownership and zero every byte after
    ; the initialized file before transferring control.
    dq kernel_bss_end - ulf_header

; -----------------------------------------------------------------------------
; Kernel Entry Point
; -----------------------------------------------------------------------------
kernel_entry:
    section .text
    global kernel_text_start
kernel_text_start:
    %include "kernel/entry/start.asm"
    %include "kernel/entry/init.asm"
    %include "kernel/entry/main.asm"

; -----------------------------------------------------------------------------
; Include Drivers & Libraries (for early boot)
; -----------------------------------------------------------------------------
%include "kernel/drivers/serial/uart.asm"
%include "kernel/arch/x86_64/cpu.asm"
%include "kernel/arch/x86_64/gdt.asm"
%include "kernel/arch/x86_64/interrupts.asm"
%include "lib/mem/mem.asm"
%include "kernel/arch/x86_64/smp.asm"
%include "kernel/arch/x86_64/vtd.asm"
%include "kernel/arch/x86_64/pci.asm"
%include "lib/io/intr/vector.asm"
%include "kernel/arch/x86_64/pci_msi.asm"
%include "kernel/arch/x86_64/pci_msix.asm"
%include "kernel/arch/x86_64/pci_edu.asm"
%include "kernel/arch/x86_64/pci_e1000e.asm"
%include "kernel/arch/x86_64/ioapic.asm"
%include "lib/unet/core/link/net_link.asm"
%include "lib/hw/ucpu/mtrr.asm"
%include "lib/hw/ucpu/pat.asm"
%include "lib/hw/ucpu/topology.asm"
%include "lib/hw/ucpu/pinning.asm"
%include "lib/hw/unuma/detect.asm"
%include "lib/hw/unuma/affinity.asm"
%include "lib/hw/unuma/distance.asm"
%include "lib/hw/ugpu/detect.asm"
%include "lib/hw/ugpu/pcie.asm"
%include "lib/hw/ugpu/nvlink.asm"
%include "lib/hw/uhbm/layout.asm"
%include "lib/hw/ucxl/cxl.asm"
%include "lib/hw/uhwloc/hwloc.asm"
%include "kernel/drivers/gpu/fb.asm"
%include "kernel/sched/fiber.asm"
%include "kernel/sched/fiber_canary.asm"
%include "kernel/sched/fiber_pkey.asm"
%include "kernel/sched/fiber_guard.asm"
%include "kernel/sched/fiber_supervisor.asm"
%include "kernel/sched/smp_mpmc.asm"
%include "kernel/sched/sched.asm"
%include "lib/ufile/ufile.asm"
%include "lib/ufile/ufile_sanitize.asm"
%include "lib/ufile/ufile_entropy.asm"
%include "lib/ufile/ufile_hash.asm"
%include "lib/ufile/ufile_engine.asm"
%include "lib/ufile/ufile_transpose.asm"
%include "lib/ufile/signatures/fs_signatures.asm"
%include "lib/ufile/signatures/ai_signatures.asm"
%include "lib/ufile/signatures/exec_signatures.asm"
%include "lib/crypto/uhash/sha256/sha256.asm"
%include "lib/crypto/uhash/blake3/blake3.asm"
%include "lib/crypto/uhash/blake2/blake2b.asm"
%include "lib/crypto/uhash/blake2/blake2s.asm"
%include "lib/crypto/uhash/sha512/sha512.asm"
%include "lib/crypto/uhash/sha3/sha3.asm"
%include "lib/crypto/uhash/uhash.asm"
%include "lib/crypto/usign/ed25519/ed25519.asm"
%include "lib/crypto/usign/ecdsa/ecdsa_p256.asm"
%include "lib/crypto/usign/rsa/rsa_pss.asm"
%include "lib/crypto/upqc/upqc.asm"
%include "lib/crypto/usign/formats/raw.asm"
%include "lib/crypto/usign/formats/pem.asm"
%include "lib/crypto/usign/formats/pkcs7.asm"
%include "lib/crypto/usign/formats/upk_sig.asm"
%include "lib/crypto/usign/usign.asm"
%include "lib/crypto/ukdf/hkdf/hkdf.asm"
%include "lib/crypto/ukdf/argon2/argon2.asm"
%include "lib/crypto/ukdf/pbkdf2/pbkdf2.asm"
%include "lib/crypto/ukdf/ukdf.asm"
%include "lib/crypto/ucrypt/ucrypt.asm"
%include "lib/crypto/upass/upass.asm"   ; After ucrypt/ukdf: needs hmac + argon2id
%include "lib/time/delay.asm"
%include "lib/time/timer_wheel.asm"
%include "lib/time/tsc.asm"         ; Before mono: supplies tsc_read/elapsed
%include "lib/time/mono.asm"        ; Monotonic clock; usrauth TTLs depend on it
%include "lib/time/rtc.asm"         ; Before time.asm: supplies rtc_init
%define TIME_NATIVE_EMBEDDED 1
%include "lib/cal/gregorian.asm"
%include "lib/cal/civil.asm"
%include "lib/time/rtc_native.asm"
%include "lib/time/native.asm"
%include "lib/time/time.asm"        ; time_init: the only caller of
                                     ; tsc_calibrate_pit anywhere in the tree.
                                     ; Without this file in the build,
                                     ; tsc_freq_hz can never become anything
                                     ; but its uncalibrated 3.0 GHz default.
%include "kernel/entry/apps_time.asm"
%include "lib/urand/urand.asm"
%include "lib/ulog/ulog.asm"        ; Structured logging. Needs mem + time +
                                     ; the serial driver, all already above;
                                     ; nothing below this line should have to
                                     ; wait for it — see lib/ulog/init/
                                     ; early_init.asm for how callers before
                                     ; ulog_full_init runs still work.
%include "lib/crypto/ux509/ux509.asm"
%include "lib/ucmp/ucmp.asm"
%include "storage/ubxp/ubxp.asm"
%include "storage/uxfs/uxfs.asm"
%include "storage/uwal/uwal.asm"    ; After uxfs: uses its NVMe driver
%include "security/usrauth/usrauth.asm"   ; Reference monitor; needs crypto + time
%include "lib/unet/unet.asm"

; Static Ush bundle: object-linked independently, embedded with ULF ownership.
%include "kernel/entry/ush.asm"

%include "kernel/exec/exec.asm"     ; UBF program loader (docs/UBF_SPEC.md)

; Last: stubs for symbols the tree references but has never implemented. Being
; last means a real definition anywhere above wins, and the generator drops the
; stub on its next run.
%include "kernel/unimplemented.asm"

    section .text
    global kernel_text_end
kernel_text_end:

; Make the protection boundary explicit.  Relying on a later data object's
; alignment can place writable data in the final executable page.
align 4096, db 0xCC
kernel_end:

; -----------------------------------------------------------------------------
; kernel_bss_end — true top of the kernel's memory footprint, .bss included.
;
; kernel_end (above) is the page-aligned executable boundary after .text. The
; stamped ULF size covers .text+.data+.rodata — all bytes written to disk.
; Neither is correct for "how much RAM does the kernel occupy", because .bss —
; every global the kernel initializes to zero, including phys_state, the
; kernel stacks (kernel_stack_guard among them), smp_active_cores, all of
; it — reserves address space without contributing any bytes to the file, and
; so is invisible to both of those.
;
; lib/mem/phys/phys.asm's bitmap-placement scan used to exclude only
; [KERNEL_LOAD, kernel_true_end) — the on-disk extent — from where it would
; place its own allocation bitmap. The first free page past that boundary is
; the start of .bss, so the fix landed the bitmap on top of kernel_stack_guard
; and then filled it with 0xFF, stamping over the live, in-use kernel stack a
; few instructions into running on it. This label is `.bss`'s own, so being
; the last thing in the last include (kernel/unimplemented.asm, directly
; above) makes it — by the same section-grouping flat binaries do for .text —
; the highest address any of the kernel's zero-initialized state reaches.
; -----------------------------------------------------------------------------
    section .bss
    global kernel_bss_end
align 8
kernel_bss_end:

%endif ; KERNEL_ENTRY_ASM
