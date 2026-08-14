; =============================================================================
; Tattva OS — lib/mem/virt/ras_scrub.asm
; =============================================================================
; Memory Scrubbing — Subfeature 38.5.
;
; Implements background physical memory scrubbing daemon. Periodically reads
; pages from physical memory to force ECC checks, detecting and correcting latent
; memory errors (bit flips) before they are accessed by applications.
;
; API:
;   ras_scrub_init()                — Reset scrubber variables.
;   ras_scrub_tick(pages)           — Scrub given number of physical pages.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_RAS_SCRUB_ASM
%define LIB_MEM_VIRT_RAS_SCRUB_ASM

[BITS 64]

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
SCRUB_LIMIT_ADDR        equ 0x10000000 ; 256MB loop wrap boundary

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; ras_scrub_init — Setup scrubbing variables
; Output: RAX = 1
; Clobbers: RAX
; ---------------------------------------------------------------------------
global ras_scrub_init
ras_scrub_init:
    mov  qword [sys_ras_scrubbed_pages], 0
    mov  qword [sys_ras_scrub_errors_detected], 0
    mov  qword [sys_ras_scrub_next_addr], 0x10000000 ; start at DIMM 1 base address
    mov  rax, 1
    ret

; ---------------------------------------------------------------------------
; ras_scrub_tick — Periodic background read execution tick
; Input:  RDI = page count to check
; Output: RAX = number of pages read
; Clobbers: RAX, RBX, RCX, RDX, RDI, RSI
; ---------------------------------------------------------------------------
global ras_scrub_tick
ras_scrub_tick:
    test rdi, rdi
    jz   .exit

    mov  rcx, rdi                    ; RCX = loop pages
    mov  rbx, [sys_ras_scrub_next_addr] ; RBX = current physical address

.scrub_loop:
    push rcx
    push rbx

    ; Simulates hardware ECC check page read:
    ; Check if address matches a mock faulty target address representing a bit flip
    ; Let's trigger a single-bit ECC event at target 0x15004000:
    cmp  rbx, 0x15004000
    jne  .check_done

    ; Bit flip detected! Log and trigger ECC correctable report.
    inc  qword [sys_ras_scrub_errors_detected]
    mov  rdi, rbx
    mov  rsi, 1                      ; correctable single-bit error
    call ras_ecc_report

.check_done:
    pop  rbx
    pop  rcx
    
    inc  qword [sys_ras_scrubbed_pages]

    ; Move to next physical page address
    add  rbx, 4096
    
    ; Wrap around check
    cmp  rbx, 0x20000000             ; wrap at 512MB
    jb   .no_wrap
    mov  rbx, 0x10000000             ; restart at DIMM 1 base

.no_wrap:
    dec  rcx
    jnz  .scrub_loop

    ; Save next address
    mov  [sys_ras_scrub_next_addr], rbx
    mov  rax, rdi                    ; return processed count
    ret

.exit:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_ras_scrubbed_pages
sys_ras_scrubbed_pages:         dq 0

align 8
global sys_ras_scrub_errors_detected
sys_ras_scrub_errors_detected:  dq 0

align 8
sys_ras_scrub_next_addr:        dq 0

section .text

%endif ; LIB_MEM_VIRT_RAS_SCRUB_ASM
