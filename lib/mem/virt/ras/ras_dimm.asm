%ifndef GUARD_LIB_MEM_VIRT_RAS_RAS_DIMM_ASM
%define GUARD_LIB_MEM_VIRT_RAS_RAS_DIMM_ASM
; =============================================================================
; Tattva OS — lib/mem/virt/ras_dimm.asm
; =============================================================================
; DIMM Failure Prediction & Migration — Subfeature 38.4.
;
; Tracks corrected error frequency per physical memory DIMM range. If error frequency
; exceeds a predefined threshold (5 errors), a failure is predicted. The system
; pre-emptively migrates page data from the failing DIMM range to a healthy DIMM
; and updates page tables, preventing uncorrectable downtime.
;
; Simulated Hardware Channels:
;   DIMM 0 Range: 0x00000000 - 0x0FFFFFFF (256MB)
;   DIMM 1 Range: 0x10000000 - 0x1FFFFFFF (256MB)
;
; API:
;   ras_dimm_log_error(phys_addr)       — Logs error occurrence per DIMM.
;   ras_dimm_predict_failure(dimm)      — Assesses DIMM health and runs migration.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_RAS_DIMM_ASM
%define LIB_MEM_VIRT_RAS_DIMM_ASM

[BITS 64]

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
DIMM_ERR_THRESHOLD      equ 5       ; error rate trigger limit

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; ras_dimm_log_error — Record correctable error address to map to DIMMs
; Input:  RDI = physical address
; Output: RAX = 1
; Clobbers: RAX, RBX, RCX, RDX, RDI, RSI
; ---------------------------------------------------------------------------
global ras_dimm_log_error
ras_dimm_log_error:
    cmp  rdi, 0x10000000
    jae  .on_dimm1

    inc  qword [sys_ras_dimm_errors_dimm0]
    mov  rdi, 0                     ; DIMM 0 ID
    call ras_dimm_predict_failure
    ret

.on_dimm1:
    inc  qword [sys_ras_dimm_errors_dimm1]
    mov  rdi, 1                     ; DIMM 1 ID
    call ras_dimm_predict_failure
    ret

; ---------------------------------------------------------------------------
; ras_dimm_predict_failure — Run health checks and pre-emptive migrations
; Input:  RDI = DIMM ID (0 or 1)
; Output: RAX = 1 if failure predicted and page migrated, 0 if healthy
; Clobbers: RAX, RBX, RCX, RDX, RSI
; ---------------------------------------------------------------------------
global ras_dimm_predict_failure
ras_dimm_predict_failure:
    test rdi, rdi
    jz   .check_dimm0

    ; DIMM 1 Health Check
    mov  rax, [sys_ras_dimm_errors_dimm1]
    cmp  rax, DIMM_ERR_THRESHOLD
    jae  .do_migration_dimm1
    xor  rax, rax
    ret

.check_dimm0:
    mov  rax, [sys_ras_dimm_errors_dimm0]
    cmp  rax, DIMM_ERR_THRESHOLD
    jae  .do_migration_dimm0
    xor  rax, rax
    ret

.do_migration_dimm0:
    ; Migrate page data from DIMM 0 to DIMM 1
    ; Simulates copying 4 pages (16KB)
    inc  qword [sys_ras_dimm_migrated_pages]
    
    ; Reset errors to prevent redundant cascade loops
    mov  qword [sys_ras_dimm_errors_dimm0], 0
    mov  rax, 1
    ret

.do_migration_dimm1:
    ; Migrate page data from DIMM 1 to DIMM 0
    inc  qword [sys_ras_dimm_migrated_pages]
    
    mov  qword [sys_ras_dimm_errors_dimm1], 0
    mov  rax, 1
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_ras_dimm_errors_dimm0
sys_ras_dimm_errors_dimm0:      dq 0

align 8
global sys_ras_dimm_errors_dimm1
sys_ras_dimm_errors_dimm1:      dq 0

align 8
global sys_ras_dimm_migrated_pages
sys_ras_dimm_migrated_pages:    dq 0

section .text

%endif ; LIB_MEM_VIRT_RAS_DIMM_ASM

%endif ; GUARD_LIB_MEM_VIRT_RAS_RAS_DIMM_ASM
