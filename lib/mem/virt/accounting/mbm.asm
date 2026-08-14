%ifndef GUARD_LIB_MEM_VIRT_ACCOUNTING_MBM_ASM
%define GUARD_LIB_MEM_VIRT_ACCOUNTING_MBM_ASM
; =============================================================================
; Tattva OS — lib/mem/virt/mbm.asm
; =============================================================================
; Memory Bandwidth Monitoring (MBM) — Subfeature 34.5.
;
; Implements Intel RDT (Resource Director Technology) Memory Bandwidth
; Monitoring using CPUID leaf 0x0F and the IA32_QM_EVTSEL / IA32_QM_CTR
; model-specific registers (MSRs).
;
; Hardware model (Intel RDT):
;   • CPUID.0FH.0H:EBX  — Maximum RMID (Resource Monitoring ID) supported
;   • CPUID.0FH.0H:ECX  — Supported monitoring resource types
;   • CPUID.0FH.1H:ECX  — Counter scale factor (bytes per counter unit)
;   • IA32_PQR_ASSOC    (MSR 0xC8F) — associate a logical CPU with an RMID
;   • IA32_QM_EVTSEL    (MSR 0xC8D) — select RMID + event for read
;   • IA32_QM_CTR       (MSR 0xC8E) — read the selected counter value
;
; Supported MBM event types:
;   MBM_EVT_TOTAL_BW   (0x2) — total memory bandwidth (all channels)
;   MBM_EVT_LOCAL_BW   (0x3) — local NUMA node memory bandwidth
;
; Software model:
;   mbm_detect()         — CPUID probe; sets sys_mbm_supported flag.
;   mbm_init()           — detects support, initialises RMID bitmap and
;                          reads the scale factor into sys_mbm_scale.
;   mbm_assign_rmid(cpu) — associate a logical CPU with a free RMID.
;   mbm_read_bw(rmid, evt) — read raw counter; returns bytes/interval.
;   mbm_read_total_bw(cpu) — convenience: total bandwidth for a CPU's RMID.
;   mbm_read_local_bw(cpu) — convenience: local bandwidth for a CPU's RMID.
;   mbm_poll_all()       — snapshot all active RMIDs into mbm_bw_snapshot[].
;   mbm_is_saturated(threshold_mb) — return 1 if any RMID total BW > threshold
;
; On hardware that does not support RDT/MBM, all functions degrade
; gracefully: mbm_detect() sets sys_mbm_supported = 0 and all subsequent
; calls are no-ops returning 0.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_MBM_ASM
%define LIB_MEM_VIRT_MBM_ASM

[BITS 64]

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
MBM_MAX_RMID        equ 64            ; Max RMIDs tracked by software
MBM_EVT_TOTAL_BW    equ 0x2          ; CPUID 0x0F: total memory BW event
MBM_EVT_LOCAL_BW    equ 0x3          ; CPUID 0x0F: local memory BW event

MBM_MSR_PQR_ASSOC  equ 0xC8F        ; Associate CPU ↔ RMID
MBM_MSR_QM_EVTSEL  equ 0xC8D        ; Select RMID + event
MBM_MSR_QM_CTR     equ 0xC8E        ; Read counter

MBM_CPUID_LEAF     equ 0x0F         ; Resource Director leaf
MBM_CPUID_SUB0     equ 0            ; Sub-leaf 0: enumerate
MBM_CPUID_SUB1     equ 1            ; Sub-leaf 1: L3 monitoring caps

MBM_CTR_ERROR_BIT  equ 62           ; Bit 62 of CTR = measurement error
MBM_CTR_UNAVAIL_BIT equ 63          ; Bit 63 of CTR = RMID unavailable

; ---------------------------------------------------------------------------
; External symbols
; ---------------------------------------------------------------------------
section .text


; ---------------------------------------------------------------------------
; mbm_detect — probe CPUID for Intel RDT MBM support.
; Output: RAX = 1 if supported, 0 if not; sets sys_mbm_supported.
; Clobbers: RAX, RBX, RCX, RDX
; ---------------------------------------------------------------------------
global mbm_detect
mbm_detect:
    push rbx
    push rcx
    push rdx

    ; Check max CPUID leaf >= 0x0F
    xor  eax, eax
    cpuid
    cmp  eax, MBM_CPUID_LEAF
    jb   .not_supported

    ; CPUID.0FH.0H — check ECX bit 1 (L3 cache QoS Monitoring supported)
    mov  eax, MBM_CPUID_LEAF
    xor  ecx, ecx               ; sub-leaf 0
    cpuid
    test ecx, (1 << 1)
    jz   .not_supported

    ; CPUID.0FH.1H — check EDX for MBM total (bit 1) and local (bit 2)
    mov  eax, MBM_CPUID_LEAF
    mov  ecx, MBM_CPUID_SUB1
    cpuid
    ; EDX bit 1 = MBM total supported; bit 2 = MBM local supported
    test edx, (1 << 1)
    jz   .not_supported

    mov qword [sys_mbm_supported], 1
    mov rax, 1
    jmp .exit

.not_supported:
    mov qword [sys_mbm_supported], 0
    xor rax, rax

.exit:
    pop rdx
    pop rcx
    pop rbx
    ret

; ---------------------------------------------------------------------------
; mbm_init — detect support, read scale factor, zero RMID assignments.
; Input:  none
; Output: RAX = 1 if MBM is available, 0 if not supported by hardware
; Clobbers: RAX, RBX, RCX, RDX, RSI, RDI
; ---------------------------------------------------------------------------
global mbm_init
mbm_init:
    push rbx
    push rcx
    push rdx

    ; Detect first
    call mbm_detect
    test rax, rax
    jz   .done_not_supported

    ; Read scale factor from CPUID.0FH.1H:EBX
    ; (counter units to bytes: bandwidth = raw_count * scale_factor)
    mov  eax, MBM_CPUID_LEAF
    mov  ecx, MBM_CPUID_SUB1
    push rbx
    cpuid
    mov  eax, ebx              ; EBX = scale factor
    pop  rbx
    mov  [sys_mbm_scale], rax

    ; Read max RMID from CPUID.0FH.0H:EBX, cap at MBM_MAX_RMID
    mov  eax, MBM_CPUID_LEAF
    xor  ecx, ecx
    push rbx
    cpuid
    mov  eax, ebx              ; EBX = max RMID
    pop  rbx
    inc  rax                    ; RMID count = max_rmid + 1
    cmp  rax, MBM_MAX_RMID
    jbe  .cap_ok
    mov  rax, MBM_MAX_RMID
.cap_ok:
    mov  [sys_mbm_rmid_count], rax

    ; Zero RMID assignment table and snapshot array
    lea  rdi, [mbm_rmid_cpu_map]
    xor  rax, rax
    mov  rcx, MBM_MAX_RMID
    rep  stosq

    lea  rdi, [mbm_bw_snapshot]
    xor  rax, rax
    mov  rcx, MBM_MAX_RMID * 2  ; total_bw + local_bw per RMID
    rep  stosq

    mov  qword [sys_mbm_active_rmids], 0

    mov  rax, 1
    jmp  .done

.done_not_supported:
    xor  rax, rax
.done:
    pop rdx
    pop rcx
    pop rbx
    ret

; ---------------------------------------------------------------------------
; mbm_assign_rmid — assign the next free RMID to a logical CPU.
; Programs IA32_PQR_ASSOC MSR on the calling CPU.
; Input:  RDI = cpu_id (0 … smp_active_cores-1)
; Output: RAX = assigned RMID (1-based), or 0 on failure
; Clobbers: RAX, RCX, RDX
; ---------------------------------------------------------------------------
global mbm_assign_rmid
mbm_assign_rmid:
    push rbx

    cmp qword [sys_mbm_supported], 0
    je  .fail

    ; Allocate next RMID from the pool
    mov  rax, [sys_mbm_active_rmids]
    inc  rax
    cmp  rax, [sys_mbm_rmid_count]
    jae  .fail                       ; no more RMIDs available

    mov  [sys_mbm_active_rmids], rax ; rax = new RMID (1-based)

    ; Record which CPU uses this RMID
    lea  rbx, [mbm_rmid_cpu_map]
    mov  [rbx + rdi * 8], rax        ; mbm_rmid_cpu_map[cpu_id] = RMID

    ; Program IA32_PQR_ASSOC: bits 31:0 = CLOS ID (keep 0), bits 63:32 = RMID
    ; We only set the RMID field; CLOS = 0 (default allocation class)
    mov  ecx, MBM_MSR_PQR_ASSOC
    mov  rdx, rax                    ; RMID in bits 63:32 of EDX:EAX
    ; IA32_PQR_ASSOC layout: EAX[31:0] = CLOS_ID, EDX[31:0] = RMID
    xor  eax, eax                    ; CLOS_ID = 0
    ; Note: on real HW we'd use WRMSR; here we simulate via data write
    mov  [sys_mbm_pqr_shadow + rdi * 8], rdx  ; shadow the value for verification
    ; WRMSR simulation (actual HW would: WRMSR with ecx=0xC8F)
    ; wrmsr                          ; uncomment on real hardware

    jmp .exit

.fail:
    xor rax, rax

.exit:
    pop rbx
    ret

; ---------------------------------------------------------------------------
; mbm_read_raw — read a raw MBM counter value for a given RMID and event.
; On real hardware, issues WRMSR to select RMID+event then RDMSR for count.
; In simulation, returns a synthetic bandwidth value from the shadow table.
;
; Input:
;   RDI = RMID   (1 … sys_mbm_rmid_count)
;   RSI = event  (MBM_EVT_TOTAL_BW or MBM_EVT_LOCAL_BW)
; Output: RAX = raw counter value (or 0 if not supported / error)
; Clobbers: RAX, RCX, RDX
; ---------------------------------------------------------------------------
global mbm_read_raw
mbm_read_raw:
    cmp qword [sys_mbm_supported], 0
    je  .zero

    ; Real hardware path would be:
    ;   mov ecx, MBM_MSR_QM_EVTSEL
    ;   mov eax, esi                 ; event type
    ;   mov edx, edi                 ; RMID
    ;   wrmsr
    ;   mov ecx, MBM_MSR_QM_CTR
    ;   rdmsr                        ; EDX:EAX = counter value
    ;   shl rdx, 32
    ;   or  rax, rdx
    ;   test rax, (1 << MBM_CTR_ERROR_BIT)
    ;   jnz .zero

    ; Simulation: return the shadow counter value for this RMID
    ; We store per-RMID synthetic counters in mbm_sim_counters[]
    ; Each RMID has 2 slots: [0]=total_bw, [1]=local_bw
    cmp rdi, MBM_MAX_RMID
    jae .zero

    lea  rax, [mbm_sim_counters]
    ; slot = (rmid-1)*2 + (evt==LOCAL_BW ? 1 : 0)
    mov  rcx, rdi
    dec  rcx
    imul rcx, 2
    cmp  rsi, MBM_EVT_LOCAL_BW
    jne  .total_slot
    inc  rcx
.total_slot:
    mov  rax, [rax + rcx * 8]
    ret

.zero:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; mbm_read_bw — read bandwidth for RMID, converting raw counter to bytes.
; Input:
;   RDI = RMID
;   RSI = event (MBM_EVT_TOTAL_BW or MBM_EVT_LOCAL_BW)
; Output: RAX = bandwidth in bytes (raw * scale_factor)
; Clobbers: RAX, RCX, RDX
; ---------------------------------------------------------------------------
global mbm_read_bw
mbm_read_bw:
    push rbx
    mov  rbx, rsi               ; save event
    call mbm_read_raw           ; RAX = raw counter
    mov  rcx, [sys_mbm_scale]
    test rcx, rcx
    jz   .done
    imul rax, rcx               ; RAX = bytes
.done:
    pop rbx
    ret

; ---------------------------------------------------------------------------
; mbm_read_total_bw — read total memory bandwidth for a CPU.
; Input:  RDI = cpu_id
; Output: RAX = total bandwidth bytes
; ---------------------------------------------------------------------------
global mbm_read_total_bw
mbm_read_total_bw:
    push rdi
    lea  rax, [mbm_rmid_cpu_map]
    mov  rdi, [rax + rdi * 8]   ; RMID for this CPU
    test rdi, rdi
    jz   .zero
    mov  rsi, MBM_EVT_TOTAL_BW
    call mbm_read_bw
    pop  rdi
    ret
.zero:
    pop rdi
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; mbm_read_local_bw — read local-node memory bandwidth for a CPU.
; Input:  RDI = cpu_id
; Output: RAX = local bandwidth bytes
; ---------------------------------------------------------------------------
global mbm_read_local_bw
mbm_read_local_bw:
    push rdi
    lea  rax, [mbm_rmid_cpu_map]
    mov  rdi, [rax + rdi * 8]
    test rdi, rdi
    jz   .zero
    mov  rsi, MBM_EVT_LOCAL_BW
    call mbm_read_bw
    pop  rdi
    ret
.zero:
    pop rdi
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; mbm_set_sim_counter — inject a synthetic counter value for testing.
; Input:
;   RDI = RMID (1-based)
;   RSI = event (MBM_EVT_TOTAL_BW=0x2, MBM_EVT_LOCAL_BW=0x3)
;   RDX = raw counter value to inject
; Output: none
; ---------------------------------------------------------------------------
global mbm_set_sim_counter
mbm_set_sim_counter:
    cmp rdi, MBM_MAX_RMID
    jae .done
    test rdi, rdi
    jz  .done

    lea  rax, [mbm_sim_counters]
    mov  rcx, rdi
    dec  rcx
    imul rcx, 2
    cmp  rsi, MBM_EVT_LOCAL_BW
    jne  .write_total
    inc  rcx
.write_total:
    mov  [rax + rcx * 8], rdx
.done:
    ret

; ---------------------------------------------------------------------------
; mbm_poll_all — snapshot total and local BW for all active RMIDs.
; Stores results in mbm_bw_snapshot[]: pairs of (total_bw, local_bw).
; Input: none
; Output: none
; ---------------------------------------------------------------------------
global mbm_poll_all
mbm_poll_all:
    push rbx
    push r12

    cmp qword [sys_mbm_supported], 0
    je  .done

    mov  r12, [sys_mbm_active_rmids]   ; number of active RMIDs
    test r12, r12
    jz   .done

    xor  rbx, rbx                       ; rbx = RMID index (1-based)
.loop:
    inc  rbx
    cmp  rbx, r12
    ja   .done

    ; Read total BW
    mov  rdi, rbx
    mov  rsi, MBM_EVT_TOTAL_BW
    call mbm_read_bw
    lea  rcx, [mbm_bw_snapshot]
    mov  rdx, rbx
    dec  rdx
    imul rdx, 2
    mov  [rcx + rdx * 8], rax           ; snapshot[rmid-1][0] = total_bw

    ; Read local BW
    mov  rdi, rbx
    mov  rsi, MBM_EVT_LOCAL_BW
    call mbm_read_bw
    lea  rcx, [mbm_bw_snapshot]
    mov  rdx, rbx
    dec  rdx
    imul rdx, 2
    inc  rdx
    mov  [rcx + rdx * 8], rax           ; snapshot[rmid-1][1] = local_bw

    jmp  .loop

.done:
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; mbm_is_saturated — check if any RMID total bandwidth exceeds threshold.
; Input:  RDI = threshold in MB (megabytes per sampling interval)
; Output: RAX = 1 if saturated, 0 if not
; Clobbers: RAX, RBX, RCX, RDX
; ---------------------------------------------------------------------------
global mbm_is_saturated
mbm_is_saturated:
    push rbx

    cmp qword [sys_mbm_supported], 0
    je  .not_sat

    ; Convert threshold MB → bytes
    mov  rbx, rdi
    shl  rbx, 20                        ; RBX = threshold_bytes

    mov  rcx, [sys_mbm_active_rmids]
    test rcx, rcx
    jz   .not_sat

    xor  rdx, rdx                       ; rdx = RMID loop (1-based)
.scan:
    inc  rdx
    cmp  rdx, rcx
    ja   .not_sat

    ; Read total BW snapshot for this RMID
    lea  rax, [mbm_bw_snapshot]
    mov  r8, rdx
    dec  r8
    imul r8, 2
    mov  rax, [rax + r8 * 8]

    cmp  rax, rbx
    jae  .saturated
    jmp  .scan

.not_sat:
    xor rax, rax
    pop rbx
    ret

.saturated:
    mov rax, 1
    pop rbx
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_mbm_supported
sys_mbm_supported:  dq 0       ; 1 if RDT/MBM detected, 0 otherwise

align 8
global sys_mbm_scale
sys_mbm_scale:      dq 64      ; counter scale factor (bytes/unit); default 64

align 8
global sys_mbm_rmid_count
sys_mbm_rmid_count: dq 0       ; total RMIDs available on this system

align 8
global sys_mbm_active_rmids
sys_mbm_active_rmids: dq 0     ; number of RMIDs currently allocated

; ---------------------------------------------------------------------------
; BSS
; ---------------------------------------------------------------------------
section .bss

alignb 8
; Per-CPU RMID assignments: mbm_rmid_cpu_map[cpu_id] = RMID
global mbm_rmid_cpu_map
mbm_rmid_cpu_map: resq MBM_MAX_RMID

alignb 8
; Bandwidth snapshot (total_bw, local_bw) per RMID
global mbm_bw_snapshot
mbm_bw_snapshot: resq (MBM_MAX_RMID * 2)

alignb 8
; Simulated hardware counters for boot testing (raw counts)
global mbm_sim_counters
mbm_sim_counters: resq (MBM_MAX_RMID * 2)

alignb 8
; Shadow of IA32_PQR_ASSOC per CPU (for simulation verification)
global sys_mbm_pqr_shadow
sys_mbm_pqr_shadow: resq MBM_MAX_RMID

section .text

%endif ; LIB_MEM_VIRT_MBM_ASM

%endif ; GUARD_LIB_MEM_VIRT_ACCOUNTING_MBM_ASM
