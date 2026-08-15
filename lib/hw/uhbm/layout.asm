; =============================================================================
; Tattva OS — lib/hw/uhbm/layout.asm
; =============================================================================
; ACPI HMAT (Heterogeneous Memory Attribute Table) parser: extracts real
; per-node-pair bandwidth figures so HBM-tier nodes can be told apart from
; ordinary DDR nodes. SRAT/SLIT (lib/mem/numa) only carry a relative
; "distance" byte — HMAT is the ACPI table that actually reports MB/s.
;
; Parses HMAT sub-structure Type 1 (System Locality Latency and Bandwidth
; Information) with Data Type = 3 (Access Bandwidth). Type 0 (Memory
; Proximity Domain Attributes) and Type 2 (Memory Side Cache Information)
; are not parsed — nothing downstream needs them yet, and adding either
; is a bounded, separate extension of this same loop.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_HW_UHBM_LAYOUT_ASM
%define LIB_HW_UHBM_LAYOUT_ASM

[BITS 64]

UHBM_MAX_NODES equ 8
HMAT_TYPE_LOCALITY   equ 1
HMAT_DATA_ACCESS_BW  equ 3

struc uhbm_bw_t
    .mbps           resd 1      ; 0 = no entry recorded for this pair
endstruc

section .bss
global uhbm_bandwidth_matrix
global uhbm_node_count
; uhbm_bandwidth_matrix[from * UHBM_MAX_NODES + to] = MB/s (0 = unknown)
uhbm_bandwidth_matrix: resb uhbm_bw_t_size * UHBM_MAX_NODES * UHBM_MAX_NODES
uhbm_node_count:       resq 1      ; highest proximity domain index seen + 1

section .text

; -----------------------------------------------------------------------------
; uhbm_layout_init — parses the HMAT located by numa_detect_init
; (numa_hmat_phys_addr) into uhbm_bandwidth_matrix. Must run after
; numa_detect_init.
; Input:  none
; Output: RAX = number of bandwidth entries recorded (0 if no HMAT, or it
;         carried no Access Bandwidth locality structure)
; Clobbers: RAX, RBX, RCX, RDX, RSI, RDI, R8-R15
; -----------------------------------------------------------------------------
global uhbm_layout_init
uhbm_layout_init:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov qword [rel uhbm_node_count], 0
    xor r15, r15                    ; R15 = total entries recorded

    mov rbx, [rel numa_hmat_phys_addr]
    test rbx, rbx
    jz .done                        ; no HMAT located

    mov r12d, [rbx + 4]              ; HMAT table length
    cmp r12d, 40
    jbe .done                       ; smaller than the fixed HMAT header

    lea r13, [rbx + 40]              ; first sub-structure (HMAT header is 40 bytes)
    lea r14, [rbx + r12]             ; end of table

.substruct_loop:
    cmp r13, r14
    jae .done

    movzx eax, word [r13]            ; sub-structure Type
    mov ebp, [r13 + 4]                ; sub-structure Length (dword at offset 4)
    cmp ebp, 8
    jb .done                         ; sanity: too small to even hold a header

    cmp eax, HMAT_TYPE_LOCALITY
    jne .next_substruct

    call .parse_locality              ; R13 = this sub-structure's start
    add r15, rax

.next_substruct:
    add r13, rbp
    jmp .substruct_loop

.done:
    mov rax, r15
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ---- internal: parse one Type-1 System Locality Latency/Bandwidth struct ----
; Input:  R13 = pointer to the sub-structure, EBP = its Length
; Output: RAX = number of entries recorded from this sub-structure
; Clobbers: RAX, RBX, RCX, RDX, RSI, RDI, R8, R9, R10, R11 (R12-R15, RBP
;           are the caller's loop state and must survive)
.parse_locality:
    push rbx
    push r12

    movzx eax, byte [r13 + 8]        ; Flags (Memory Hierarchy in bits[3:0])
    movzx ecx, byte [r13 + 9]        ; Data Type
    cmp ecx, HMAT_DATA_ACCESS_BW
    jne .locality_skip                ; only Access Bandwidth is recorded

    mov r8d, [r13 + 12]               ; N = number of initiator domains
    mov r9d, [r13 + 16]               ; M = number of target domains
    cmp r8d, UHBM_MAX_NODES
    ja .locality_skip                 ; more initiators than we can index — skip
    cmp r9d, UHBM_MAX_NODES
    ja .locality_skip

    ; Entry Base Unit: 8-byte multiplier for every raw entry value below.
    ; HMAT expresses it in units of 1 MB/s already for bandwidth structures.
    mov r10, [r13 + 24]               ; Entry Base Unit
    test r10, r10
    jnz .base_unit_ok
    mov r10, 1                        ; guard against a malformed 0 multiplier
.base_unit_ok:

    lea r11, [r13 + 32]               ; initiator domain list (N dwords)
    lea rbx, [r11 + r8 * 4]           ; target domain list (M dwords), right after
    lea r12, [rbx + r9 * 4]           ; entry array (N*M words), right after that

    xor rcx, rcx                      ; RCX = initiator index i
    xor rax, rax                      ; RAX = entries recorded (return value)
.init_loop:
    cmp rcx, r8
    jae .locality_done

    mov edx, [r11 + rcx * 4]          ; initiator proximity domain id
    cmp edx, UHBM_MAX_NODES
    jae .init_next

    xor rsi, rsi                      ; RSI = target index j
.target_loop:
    cmp rsi, r9
    jae .init_next

    mov edi, [rbx + rsi * 4]          ; target proximity domain id
    cmp edi, UHBM_MAX_NODES
    jae .target_next

    ; entry[i][j] is a word at entry_array + (i*M + j)*2. Deliberately kept
    ; off R9 (M) below: R9 is the .target_loop bound check on every
    ; iteration (cmp rsi, r9 above), so nothing in this body may touch it —
    ; an earlier draft loaded the raw entry into R9 here and a second time
    ; further down for the node-count tracking, both of which corrupted the
    ; loop bound on the following iteration.
    mov r8d, ecx
    imul r8, r9
    add r8, rsi
    movzx r8d, word [r12 + r8 * 2]    ; R8 = raw entry (index no longer needed)
    test r8d, r8d
    jz .target_next                   ; 0xFFFF/0 both mean "no data" in practice; skip zero

    imul r8, r10                      ; R8 = MB/s = raw entry * Entry Base Unit

    ; Store into uhbm_bandwidth_matrix[edx * UHBM_MAX_NODES + edi]
    push rax
    mov eax, edx
    imul eax, UHBM_MAX_NODES
    add eax, edi
    mov [rel uhbm_bandwidth_matrix + rax * uhbm_bw_t_size], r8d
    pop rax
    inc rax

    ; Track the highest proximity domain index observed. RAX is safe to use
    ; as scratch here (push/pop around it) — R8/R9/R10/R11/RBX/R12 all hold
    ; live loop/addressing state that must not move.
    push rax
    mov eax, edx
    inc eax
    cmp rax, [rel uhbm_node_count]
    jbe .skip_from_count
    mov [rel uhbm_node_count], rax
.skip_from_count:
    mov eax, edi
    inc eax
    cmp rax, [rel uhbm_node_count]
    jbe .restore_count_scratch
    mov [rel uhbm_node_count], rax
.restore_count_scratch:
    pop rax

.target_next:
    inc rsi
    jmp .target_loop

.init_next:
    inc rcx
    jmp .init_loop

.locality_done:
    pop r12
    pop rbx
    ret

.locality_skip:
    xor rax, rax
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uhbm_bandwidth — bandwidth from one NUMA node to another, per HMAT
; Input:
;   RDI = node_from, RSI = node_to
; Output:
;   RAX = MB/s, or 0 if out of range or never recorded
; -----------------------------------------------------------------------------
global uhbm_bandwidth
uhbm_bandwidth:
    cmp rdi, UHBM_MAX_NODES
    jae .zero
    cmp rsi, UHBM_MAX_NODES
    jae .zero

    mov eax, edi
    imul eax, UHBM_MAX_NODES
    add eax, esi
    mov eax, [rel uhbm_bandwidth_matrix + rax * uhbm_bw_t_size]
    ret

.zero:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; uhbm_is_high_bandwidth_node — flags a node as an HBM-class tier: its best
; bandwidth to any initiator is at least 4x the lowest non-zero bandwidth
; recorded anywhere in the matrix (a relative test, since HMAT gives no
; fixed "this is HBM" flag — DDR5 vs. HBM3 bandwidth commonly differs by an
; order of magnitude, so a 4x threshold has margin against normal DDR
; channel-count/speed variation between nodes on the same system).
; Input:
;   RDI = node_id
; Output:
;   RAX = 1 if high-bandwidth relative to the system's lowest recorded
;         tier, 0 if not or if no HMAT data exists
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global uhbm_is_high_bandwidth_node
uhbm_is_high_bandwidth_node:
    push rbx
    push r12
    push r13
    push r14

    cmp rdi, UHBM_MAX_NODES
    jae .no
    mov r12, rdi                     ; R12 = target node

    mov r13, [rel uhbm_node_count]
    test r13, r13
    jz .no

    xor r14, r14                     ; R14 = best bandwidth for the target node
    mov ebx, 0xFFFFFFFF                ; RBX = lowest non-zero bandwidth system-wide
                                       ; (mov r32,imm32 zero-extends — avoids the
                                       ; sign-extending mov/cmp r64,imm32 encodings)
    xor rcx, rcx                     ; RCX = from-node index
.scan_from:
    cmp rcx, r13
    jae .scan_done

    xor rdx, rdx                     ; RDX = to-node index
.scan_to:
    cmp rdx, r13
    jae .scan_from_next

    push rcx
    push rdx
    mov rdi, rcx
    mov rsi, rdx
    call uhbm_bandwidth
    pop rdx
    pop rcx

    test eax, eax
    jz .scan_to_next

    cmp eax, ebx
    jae .not_new_min
    mov ebx, eax
.not_new_min:

    cmp rdx, r12                     ; is this entry's target our node of interest?
    jne .scan_to_next
    cmp eax, r14d
    jbe .scan_to_next
    mov r14d, eax

.scan_to_next:
    inc rdx
    jmp .scan_to

.scan_from_next:
    inc rcx
    jmp .scan_from

.scan_done:
    test r14, r14
    jz .no
    cmp ebx, 0xFFFFFFFF
    je .no                          ; nothing recorded anywhere

    mov rax, rbx
    imul rax, 4
    cmp r14, rax
    jb .no

    mov rax, 1
    jmp .done

.no:
    xor rax, rax

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_HW_UHBM_LAYOUT_ASM
