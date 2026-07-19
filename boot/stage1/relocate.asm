; =============================================================================
; Tattva OS — boot/stage1/relocate.asm
; =============================================================================
; MBR self-relocation from 0x7C00 to 0x0600.
;
; Why relocate:
;   BIOS loads the MBR to 0x7C00. Stage2 loads at 0x8000 and needs the
;   0x7C00-0x7FFF region for its stack (grows downward from 0x8000).
;   Moving the MBR to 0x0600 frees this space.
;
; Memory layout after relocation:
;   0x0000 - 0x04FF   BIOS data area (untouched)
;   0x0500 - 0x05FF   free
;   0x0600 - 0x07FF   relocated MBR (this code)
;   0x0800 - 0x7BFF   free (available for stack/buffers)
;   0x7C00 - 0x7FFF   free (was MBR, now stage2 stack)
;   0x8000 - 0xFFFF   stage2 loads here
;
; This is a standalone reference module. entry.asm has this logic inlined.
;
; Author:  Utkarsha Labs
; Target:  x86, real mode (16-bit)
; =============================================================================

%ifndef S1_RELOCATE_ASM
%define S1_RELOCATE_ASM

[BITS 16]

; =============================================================================
; s1_relocate — copy MBR from 0x7C00 to STAGE1_RELOC (0x0600)
; Input:  DS = ES = 0x0000 (must be set by caller)
; Output: none (caller must far jump to relocated code after return)
; Clobbers: SI, DI, CX
;
; Usage:
;   call s1_relocate
;   jmp 0x0000:(relocated_entry_label)
;
; The far jump is required to update CS and continue executing from the
; new location. Without it, CS still points to the old 0x7C00 region.
; =============================================================================
s1_relocate:
    cld                             ; ensure forward direction

    mov si, 0x7C00                  ; source: BIOS load address
    mov di, STAGE1_RELOC            ; dest:   0x0600
    mov cx, 256                     ; 256 words = 512 bytes
    rep movsw                       ; copy word-by-word (faster than movsb)

    ret

; =============================================================================
; s1_relocate_segments — re-initialize segments after far jump to 0x0600
; Input:  none
; Output: DS = ES = SS = 0x0000, SP = STACK_REAL
; Clobbers: AX
;
; Call this immediately after the far jump to ensure all segment registers
; are consistent with the new code location.
; =============================================================================
s1_relocate_segments:
    xor ax, ax
    mov ds, ax                      ; data segment = 0x0000
    mov es, ax                      ; extra segment = 0x0000
    mov ss, ax                      ; stack segment = 0x0000
    mov sp, STACK_REAL              ; SP = 0x7C00 (MBR region now free)
    ret

%endif ; S1_RELOCATE_ASM
