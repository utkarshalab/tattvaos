%ifndef GUARD_UNET_CORE_L3_IPV4_PMTUD_ASM
%define GUARD_UNET_CORE_L3_IPV4_PMTUD_ASM
; =============================================================================
; Tattva OS — unet/core/l3/ipv4_pmtud.asm
; =============================================================================
; Path MTU Discovery (RFC 1191, RFC 8899, RFC 4821 PLPMTUD)
;
; Implements:
;   - Classic PMTUD (RFC 1191) with DF bit
;   - Packetization Layer PMTUD (RFC 4821) for ICMP-blocked paths
;   - RFC 8899 clarifications and security fixes
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "lib/unet/unet.inc"

%define PMTU_MIN_MTU           68          ; IPv4 minimum (RFC 791)
%define PMTU_BASE_MTU          1280        ; IPv6 minimum (RFC 8200)
%define PMTU_DEFAULT_MTU       1500        ; Ethernet default
%define PMTU_AGE_TIMEOUT_MS    600000      ; 10 minutes (RFC 1191)
%define PMTU_PROBE_INTERVAL_MS 5000        ; 5 seconds
%define PMTU_MAX_PROBES        3           ; Max probes per MTU

; PMTU table entry
struc pmtu_entry_t
    .dst_ip:         resd 1      ; Destination IP (network order)
    .mtu:            resw 1      ; Current PMTU
    .state:          resb 1      ; 0=unknown, 1=probing, 2=stable
    .probe_count:    resb 1      ; Current probe attempt
    .base_mtu:       resw 1      ; Last known good MTU
    .age_timer:      resq 1      ; Timer entry for aging
    .probe_timer:    resq 1      ; Timer entry for probing
    .lock:           resd 1      ; Spinlock
    .next:           resq 1      ; Hash chain next
endstruc

%define PMTU_STATE_UNKNOWN   0
%define PMTU_STATE_PROBING   1
%define PMTU_STATE_STABLE    2

%define PMTU_TABLE_SIZE      1024      ; Power of 2

section .bss
alignb 64
pmtu_table:        resq PMTU_TABLE_SIZE
pmtu_cache:        resb kmem_cache_t_size

section .data
pmtu_cache_name:   db "ipv4_pmtu_entry", 0
pmtu_lock:         dd 0

section .text

global pmtud_init
global pmtud_get_mtu
global pmtud_update_mtu
global pmtud_icmp_unreach
global pmtud_timer_tick

; -----------------------------------------------------------------------------
; pmtud_init — Initialize PMTU subsystem
; -----------------------------------------------------------------------------
align 64
pmtud_init:
    push rbp
    mov rbp, rsp
    push rbx

    ; Clear hash table
    lea rdi, [pmtu_table]
    xor eax, eax
    mov rcx, PMTU_TABLE_SIZE
    rep stosq

    ; Create slab cache
    lea rdi, [pmtu_cache]
    lea rsi, [pmtu_cache_name]
    mov rdx, pmtu_entry_t_size
    mov rcx, 64
    xor r8, r8
    xor r9, r9
    call kmem_cache_create_in_place

    xor eax, eax
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; _pmtu_hash — Hash function for destination IP
; Input: EDI = destination IP (network order)
; Output: EAX = hash index
; -----------------------------------------------------------------------------
align 32
_pmtu_hash:
    mov eax, edi
    xor eax, eax
    shr eax, 16
    xor eax, edi
    and eax, PMTU_TABLE_SIZE - 1
    ret

; -----------------------------------------------------------------------------
; _pmtu_lookup — Find PMTU entry for destination
; Input: EDI = destination IP
; Output: RAX = pmtu_entry_t* or 0
; -----------------------------------------------------------------------------
align 64
_pmtu_lookup:
    push rbx
    push r12

    mov r12d, edi
    call _pmtu_hash
    lea rbx, [pmtu_table]
    mov rbx, [rbx + rax * 8]

.loop:
    test rbx, rbx
    jz .not_found
    cmp dword [rbx + pmtu_entry_t.dst_ip], r12d
    je .found
    mov rbx, [rbx + pmtu_entry_t.next]
    jmp .loop

.found:
    mov rax, rbx
    jmp .done

.not_found:
    xor rax, rax

.done:
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; _pmtu_alloc — Allocate new PMTU entry
; Input: EDI = destination IP
; Output: RAX = pmtu_entry_t* or 0
; -----------------------------------------------------------------------------
align 64
_pmtu_alloc:
    push rbx
    push r12
    push r13

    mov r12d, edi

    ; Allocate entry
    lea rdi, [pmtu_cache]
    call kmem_cache_alloc
    test rax, rax
    jz .fail

    mov rbx, rax
    mov dword [rbx + pmtu_entry_t.dst_ip], r12d
    mov word [rbx + pmtu_entry_t.mtu], PMTU_DEFAULT_MTU
    mov byte [rbx + pmtu_entry_t.state], PMTU_STATE_UNKNOWN
    mov byte [rbx + pmtu_entry_t.probe_count], 0
    mov word [rbx + pmtu_entry_t.base_mtu], PMTU_DEFAULT_MTU

    ; Initialize spinlock
    mov dword [rbx + pmtu_entry_t.lock], 0

    ; Insert into hash table
    call _pmtu_hash
    lea r13, [pmtu_table]
    mov rdx, [r13 + rax * 8]
    mov [rbx + pmtu_entry_t.next], rdx
    mov [r13 + rax * 8], rbx

    mov rax, rbx
    jmp .done

.fail:
    xor rax, rax

.done:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; pmtud_get_mtu — Get PMTU for destination (creates entry if needed)
; Input: EDI = destination IP (network order)
; Output: AX = MTU in bytes
; -----------------------------------------------------------------------------
align 64
pmtud_get_mtu:
    push rbp
    mov rbp, rsp
    push rbx

    mov r12d, edi

    ; Lookup existing entry
    mov edi, r12d
    call _pmtu_lookup
    test rax, rax
    jnz .found

    ; Create new entry
    mov edi, r12d
    call _pmtu_alloc
    test rax, rax
    jz .default

.found:
    movzx eax, word [rax + pmtu_entry_t.mtu]
    jmp .done

.default:
    mov eax, PMTU_DEFAULT_MTU

.done:
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; pmtud_update_mtu — Update PMTU for destination (called on ICMP or success)
; Input: EDI = destination IP, SI = new MTU (0 = use current base)
;        DX = update type (0=ICMP unreach, 1=successful probe, 2=probe failed)
; -----------------------------------------------------------------------------
align 64
pmtud_update_mtu:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov r12d, edi
    mov r13w, si
    mov r14b, dl

    mov edi, r12d
    call _pmtu_lookup
    test rax, rax
    jz .fail

    mov rbx, rax

    ; Acquire lock
.lock:
    lock bts dword [rbx + pmtu_entry_t.lock], 0
    jc .lock

    cmp r14b, 0
    je .icmp_unreach
    cmp r14b, 1
    je .probe_success
    jmp .probe_fail

.icmp_unreach:
    ; ICMP Fragmentation Needed received
    ; New MTU in SI (network order)
    movzx eax, r13w
    xchg al, ah
    cmp ax, PMTU_MIN_MTU
    jb .clamp_min
    cmp ax, [rbx + pmtu_entry_t.base_mtu]
    jle .set_mtu
    mov ax, [rbx + pmtu_entry_t.base_mtu]

.set_mtu:
    mov word [rbx + pmtu_entry_t.mtu], ax
    mov word [rbx + pmtu_entry_t.base_mtu], ax
    mov byte [rbx + pmtu_entry_t.state], PMTU_STATE_STABLE
    mov byte [rbx + pmtu_entry_t.probe_count], 0
    jmp .unlock

.probe_success:
    ; Probe succeeded at current MTU
    mov ax, [rbx + pmtu_entry_t.mtu]
    cmp r13w, ax
    jne .unlock
    ; Increase MTU (binary search towards base)
    mov ax, [rbx + pmtu_entry_t.base_mtu]
    cmp [rbx + pmtu_entry_t.mtu], ax
    jge .unlock
    ; New MTU = (current + base) / 2
    add ax, [rbx + pmtu_entry_t.mtu]
    shr ax, 1
    mov word [rbx + pmtu_entry_t.mtu], ax
    mov byte [rbx + pmtu_entry_t.state], PMTU_STATE_PROBING
    mov byte [rbx + pmtu_entry_t.probe_count], 0
    jmp .unlock

.probe_fail:
    ; Probe failed - reduce MTU
    inc byte [rbx + pmtu_entry_t.probe_count]
    cmp byte [rbx + pmtu_entry_t.probe_count], PMTU_MAX_PROBES
    jb .unlock
    ; Max probes reached - reduce MTU
    mov ax, [rbx + pmtu_entry_t.mtu]
    sub ax, 8              ; Reduce by 8 bytes (conservative)
    cmp ax, PMTU_MIN_MTU
    jb .clamp_min
    mov word [rbx + pmtu_entry_t.mtu], ax
    mov byte [rbx + pmtu_entry_t.state], PMTU_STATE_PROBING
    mov byte [rbx + pmtu_entry_t.probe_count], 0
    jmp .unlock

.clamp_min:
    mov word [rbx + pmtu_entry_t.mtu], PMTU_MIN_MTU
    mov word [rbx + pmtu_entry_t.base_mtu], PMTU_MIN_MTU

.unlock:
    lock btr dword [rbx + pmtu_entry_t.lock], 0

.fail:
    xor eax, eax
    jmp .done

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; pmtud_icmp_unreach — Process ICMP Fragmentation Needed (Type 3, Code 4)
; Input: EDI = destination IP, ESI = MTU from ICMP (network order)
; -----------------------------------------------------------------------------
align 64
pmtud_icmp_unreach:
    push rbp
    mov rbp, rsp
    push rbx

    mov ebx, esi
    xchg bl, bh          ; Convert MTU to host order

    mov edi, edi
    mov si, bx
    mov dx, 0            ; ICMP unreach type
    call pmtud_update_mtu

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; pmtud_timer_tick — Periodic PMTU maintenance (called from timer wheel)
; -----------------------------------------------------------------------------
align 64
pmtud_timer_tick:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    ; Iterate all hash buckets
    xor r12, r12
.bucket_loop:
    cmp r12d, PMTU_TABLE_SIZE
    jge .done

    lea rbx, [pmtu_table]
    mov r13, [rbx + r12 * 8]
    test r13, r13
    jz .next_bucket

    ; Process entries in this bucket
.entry_loop:
    test r13, r13
    jz .next_bucket

    ; Age out old entries
    ; TODO: Check timer expiration

    ; Handle probing state
    cmp byte [r13 + pmtu_entry_t.state], PMTU_STATE_PROBING
    je .schedule_probe

    mov r13, [r13 + pmtu_entry_t.next]
    jmp .entry_loop

.schedule_probe:
    ; Schedule probe packet at current MTU
    ; TODO: Send probe packet (TCP/UDP with size = MTU - headers)
    ; Reset probe timer
    ; Update probe timer entry

    mov r13, [r13 + pmtu_entry_t.next]
    jmp .entry_loop

.next_bucket:
    inc r12d
    jmp .bucket_loop

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; pmtud_probe — Send PMTU probe packet (internal)
; Input: RDI = pmtu_entry_t*
; -----------------------------------------------------------------------------
align 64
pmtud_probe:
    ret

%endif ; GUARD_UNET_CORE_L3_IPV4_PMTUD_ASM