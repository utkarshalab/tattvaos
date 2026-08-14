; =============================================================================
; Tattva OS — kernel/entry.asm
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

; -----------------------------------------------------------------------------
; ULF Header (32 bytes)
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
    ; Not computed, and nothing verifies it. A checksum only earns its place
    ; once the loader checks it; until then this stays an obvious placeholder
    ; rather than a real-looking value that has never been validated.
    dq 0x123456789ABCDEF0           ; checksum placeholder
    dq 0                            ; reserved

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
%include "unet/core/link/net_link.asm"
%include "lib/hw/ucpu/mtrr.asm"
%include "lib/hw/ucpu/pat.asm"
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
%include "crypto/uhash/sha256/sha256.asm"
%include "crypto/uhash/blake3/blake3.asm"
%include "crypto/uhash/blake2/blake2b.asm"
%include "crypto/uhash/blake2/blake2s.asm"
%include "crypto/uhash/sha512/sha512.asm"
%include "crypto/uhash/sha3/sha3.asm"
%include "crypto/uhash/uhash.asm"
%include "crypto/usign/ed25519/ed25519.asm"
%include "crypto/usign/ecdsa/ecdsa_p256.asm"
%include "crypto/usign/rsa/rsa_pss.asm"
%include "crypto/upqc/upqc.asm"
%include "crypto/usign/formats/raw.asm"
%include "crypto/usign/formats/pem.asm"
%include "crypto/usign/formats/pkcs7.asm"
%include "crypto/usign/formats/upk_sig.asm"
%include "crypto/usign/usign.asm"
%include "crypto/ukdf/hkdf/hkdf.asm"
%include "crypto/ukdf/argon2/argon2.asm"
%include "crypto/ukdf/pbkdf2/pbkdf2.asm"
%include "crypto/ukdf/ukdf.asm"
%include "crypto/ucrypt/ucrypt.asm"
%include "crypto/upass/upass.asm"   ; After ucrypt/ukdf: needs hmac + argon2id
%include "lib/time/delay.asm"
%include "lib/time/timer_wheel.asm"
%include "lib/time/tsc.asm"         ; Before mono: supplies tsc_read/elapsed
%include "lib/time/mono.asm"        ; Monotonic clock; usrauth TTLs depend on it
%include "lib/urand/urand.asm"
%include "crypto/ux509/ux509.asm"
%include "lib/ucmp/ucmp.asm"
%include "storage/ubxp/ubxp.asm"
%include "storage/uxfs/uxfs.asm"
%include "storage/uwal/uwal.asm"    ; After uxfs: uses its NVMe driver
%include "security/usrauth/usrauth.asm"   ; Reference monitor; needs crypto + time
%include "unet/unet.asm"

; Last: stubs for symbols the tree references but has never implemented. Being
; last means a real definition anywhere above wins, and the generator drops the
; stub on its next run.
%include "kernel/unimplemented.asm"

    section .text
    global kernel_text_end
kernel_text_end:

align 8
kernel_end:

; -----------------------------------------------------------------------------
; kernel_bss_end — true top of the kernel's memory footprint, .bss included.
;
; kernel_end (above) and the ULF header's size field both stop at the end of
; .text+.data+.rodata — the bytes actually written to the image on disk. That
; is correct for what they're for: it's exactly what a loader needs to copy.
; It is NOT correct for "how much RAM does the kernel occupy", because .bss —
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
