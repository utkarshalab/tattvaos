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
    dd kernel_end - ulf_header      ; size of binary
    dq kernel_entry                 ; dynamic entry point
    dq 0x123456789ABCDEF0           ; checksum placeholder (patched by Makefile)
    dq 0                            ; reserved

; -----------------------------------------------------------------------------
; Kernel Entry Point
; -----------------------------------------------------------------------------
kernel_entry:
    section .text
    global kernel_text_start
kernel_text_start:
    %include "entry/start.asm"
    %include "entry/init.asm"
    %include "entry/main.asm"

; -----------------------------------------------------------------------------
; Include Drivers & Libraries (for early boot)
; -----------------------------------------------------------------------------
%include "drivers/serial/uart.asm"
%include "arch/x86_64/cpu.asm"
%include "arch/x86_64/gdt.asm"
%include "arch/x86_64/interrupts.asm"
%include "lib/mem/mem.asm"
%include "unet/core/link/net_link.asm"
%include "lib/hw/ucpu/mtrr.asm"
%include "lib/hw/ucpu/pat.asm"
%include "drivers/gpu/fb.asm"
%include "sched/fiber.asm"
%include "sched/fiber_canary.asm"
%include "sched/fiber_pkey.asm"
%include "sched/fiber_guard.asm"
%include "sched/fiber_supervisor.asm"
%include "sched/smp_mpmc.asm"
%include "sched/sched.asm"
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
%include "lib/urand/urand.asm"
%include "crypto/ux509/ux509.asm"

    section .text
    global kernel_text_end
kernel_text_end:

align 8
kernel_end:

%endif ; KERNEL_ENTRY_ASM
