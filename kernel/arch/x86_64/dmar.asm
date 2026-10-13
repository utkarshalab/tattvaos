%ifndef KERNEL_ARCH_X86_64_DMAR_ASM
%define KERNEL_ARCH_X86_64_DMAR_ASM
; =============================================================================
; Intel DMA Remapping Reporting (DMAR) platform-policy validation.
; =============================================================================

[BITS 64]

DMAR_SIGNATURE             equ 0x52414D44
DMAR_HEADER_BYTES          equ 48
DMAR_MAX_TABLE_BYTES       equ 1024 * 1024
DMAR_FLAG_INTR_REMAP       equ 1 << 0
DMAR_FLAG_X2APIC_OPT_OUT   equ 1 << 1
DMAR_FLAG_DMA_CTRL_OPT_IN  equ 1 << 2

SMP_DMAR_MAX_DRHDS              equ 32
SMP_DMAR_DRHD_BYTES             equ 24
SMP_DMAR_DRHD_BASE_OFF          equ 0
SMP_DMAR_DRHD_TABLE_OFFSET_OFF  equ 8
SMP_DMAR_DRHD_SCOPE_BYTES_OFF   equ 12
SMP_DMAR_DRHD_SCOPE_COUNT_OFF   equ 16
SMP_DMAR_DRHD_SEGMENT_OFF       equ 20
SMP_DMAR_DRHD_FLAGS_OFF         equ 22
SMP_DMAR_DRHD_REG_SIZE_OFF      equ 23

SMP_DMAR_ERR_INPUT          equ 1
SMP_DMAR_ERR_SPAN           equ 2
SMP_DMAR_ERR_HEADER         equ 3
SMP_DMAR_ERR_ENTRY          equ 4
SMP_DMAR_ERR_DUPLICATE      equ 5
SMP_DMAR_ERR_CAPACITY       equ 6

section .text

; RDI=DMAR, RSI=exclusive mapped limit.
; CF=0/EAX=validated flags. CF=1 means the table cannot guide APIC policy.
global smp_dmar_policy_parse
smp_dmar_policy_parse:
    test rdi, rdi
    jz .invalid
    mov rdx, rdi
    add rdx, 36
    jc .invalid
    cmp rdx, rsi
    ja .invalid
    cmp dword [rdi], DMAR_SIGNATURE
    jne .invalid
    mov ecx, [rdi + 4]
    cmp ecx, DMAR_HEADER_BYTES
    jb .invalid
    cmp ecx, DMAR_MAX_TABLE_BYTES
    ja .invalid
    mov rdx, rdi
    add rdx, rcx
    jc .invalid
    cmp rdx, rsi
    ja .invalid
    cmp byte [rdi + 8], 1
    jne .invalid
    cmp byte [rdi + 36], 63
    ja .invalid
    mov al, [rdi + 37]
    test al, 0xF8
    jnz .invalid
    test al, DMAR_FLAG_X2APIC_OPT_OUT
    jz .flags_valid
    test al, DMAR_FLAG_INTR_REMAP
    jz .invalid
.flags_valid:
    cmp qword [rdi + 38], 0
    jne .invalid
    cmp word [rdi + 46], 0
    jne .invalid

    xor eax, eax
    mov rdx, rdi
.checksum:
    add al, [rdx]
    inc rdx
    dec ecx
    jnz .checksum
    test al, al
    jnz .invalid
    movzx eax, byte [rdi + 37]
    clc
    ret
.invalid:
    xor eax, eax
    stc
    ret

; -----------------------------------------------------------------------------
; smp_dmar_parse_drhds — validate and retain DMA-remapping hardware units
;
; RDI = DMAR identity address
; RSI = exclusive end of the currently accessible physical mapping
; RDX = output array of SMP_DMAR_DRHD_BYTES records
; ECX = output capacity
;
; CF=0: EAX=DRHD count, EDX=0.
; CF=1: EAX=0, EDX=rejection class. Partial output must be discarded.
;
; No remapping hardware is touched here. The retained table offsets let the
; later activation path revisit already-framed device scopes without storing
; raw firmware pointers in every record.
; -----------------------------------------------------------------------------
global smp_dmar_parse_drhds
smp_dmar_parse_drhds:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24

    mov r12, rdi                    ; table start
    mov r13, rsi                    ; accessible end, then exact table end
    mov r14, rdx                    ; descriptor output
    mov r15d, ecx                   ; descriptor capacity

    mov edx, SMP_DMAR_ERR_INPUT
    test r12, r12
    jz .drhd_invalid
    test r14, r14
    jz .drhd_invalid
    cmp r12, r13
    jae .drhd_invalid
    cmp r15d, 1
    jb .drhd_invalid
    cmp r15d, SMP_DMAR_MAX_DRHDS
    ja .drhd_invalid

    mov edx, SMP_DMAR_ERR_SPAN
    mov rax, r12
    add rax, DMAR_HEADER_BYTES
    jc .drhd_invalid
    cmp rax, r13
    ja .drhd_invalid
    mov ecx, [r12 + 4]
    cmp ecx, DMAR_HEADER_BYTES
    jb .drhd_header_invalid
    cmp ecx, DMAR_MAX_TABLE_BYTES
    ja .drhd_header_invalid
    mov rax, r12
    add rax, rcx
    jc .drhd_invalid
    cmp rax, r13
    ja .drhd_invalid
    mov r13, rax

    ; Reject firmware/output aliasing before emitting the first descriptor.
    mov eax, r15d
    imul rax, SMP_DMAR_DRHD_BYTES
    add rax, r14
    jc .drhd_span_invalid
    mov [rsp], rax
    cmp r14, r13
    jae .drhd_output_disjoint
    cmp r12, [rsp]
    jb .drhd_span_invalid
.drhd_output_disjoint:

    mov rdi, r12
    mov rsi, r13
    call smp_dmar_policy_parse
    jc .drhd_header_invalid

    xor ebx, ebx                    ; retained DRHD count
    mov dword [rsp + 8], 0          ; last remapping-structure type
    lea rbp, [r12 + DMAR_HEADER_BYTES]
.drhd_structure_loop:
    cmp rbp, r13
    je .drhd_structures_done
    ja .drhd_entry_invalid
    mov rax, r13
    sub rax, rbp
    cmp rax, 4
    jb .drhd_entry_invalid
    movzx ecx, word [rbp + 2]
    cmp ecx, 4
    jb .drhd_entry_invalid
    lea r11, [rbp + rcx]
    cmp r11, rbp
    jb .drhd_entry_invalid
    cmp r11, r13
    ja .drhd_entry_invalid
    movzx eax, word [rbp]
    cmp eax, [rsp + 8]              ; remapping structures are type ordered
    jb .drhd_entry_invalid
    mov [rsp + 8], eax
    test eax, eax                   ; type 0: DRHD
    jne .drhd_next_structure

    cmp ecx, 16
    jb .drhd_entry_invalid
    test byte [rbp + 4], 0xFE       ; only INCLUDE_PCI_ALL is defined
    jnz .drhd_entry_invalid
    test byte [rbp + 5], 0xF0       ; register-size exponent is low nibble
    jnz .drhd_entry_invalid
    mov r9, [rbp + 8]
    test r9, r9
    jz .drhd_entry_invalid
    movzx ecx, byte [rbp + 5]
    mov eax, 4096
    shl rax, cl
    mov rdx, rax
    dec rdx
    test r9, rdx                    ; align to the complete register-set size
    jnz .drhd_entry_invalid
    add rax, r9
    jc .drhd_entry_invalid
    mov [rsp + 16], rax             ; exclusive register-window end

    xor r8d, r8d                    ; device-scope count
    lea r10, [rbp + 16]
.drhd_scope_loop:
    cmp r10, r11
    je .drhd_scopes_done
    ja .drhd_entry_invalid
    mov rax, r11
    sub rax, r10
    cmp rax, 8
    jb .drhd_entry_invalid
    movzx ecx, byte [r10 + 1]
    cmp ecx, 8                      ; six-byte header plus at least one path
    jb .drhd_entry_invalid
    test ecx, 1
    jnz .drhd_entry_invalid
    lea rdx, [r10 + rcx]
    cmp rdx, r10
    jb .drhd_entry_invalid
    cmp rdx, r11
    ja .drhd_entry_invalid
    movzx eax, byte [r10]
    cmp eax, 1
    jb .drhd_entry_invalid
    cmp eax, 5
    ja .drhd_entry_invalid
    cmp byte [r10 + 2], 0           ; reserved outside SIDP structures
    jne .drhd_entry_invalid
    cmp byte [r10 + 3], 0
    jne .drhd_entry_invalid
    cmp eax, 2
    ja .drhd_scope_enum_valid
    cmp byte [r10 + 4], 0           ; reserved for PCI endpoint/subhierarchy
    jne .drhd_entry_invalid
.drhd_scope_enum_valid:
    test byte [rbp + 4], 1
    jz .drhd_scope_type_valid
    cmp eax, 2                      ; INCLUDE_ALL forbids PCI scopes only
    jbe .drhd_entry_invalid
.drhd_scope_type_valid:
    lea rax, [r10 + 6]
.drhd_path_loop:
    cmp rax, rdx
    je .drhd_scope_done
    movzx esi, byte [rax]
    cmp esi, 31
    ja .drhd_entry_invalid
    movzx esi, byte [rax + 1]
    cmp esi, 7
    ja .drhd_entry_invalid
    add rax, 2
    jmp .drhd_path_loop
.drhd_scope_done:
    inc r8d
    mov r10, rdx
    jmp .drhd_scope_loop

.drhd_scopes_done:
    xor edx, edx
.drhd_duplicate_loop:
    cmp edx, ebx
    jae .drhd_unique
    mov eax, edx
    imul rax, SMP_DMAR_DRHD_BYTES
    lea r10, [r14 + rax]
    mov rax, [r10 + SMP_DMAR_DRHD_BASE_OFF]
    cmp r9, rax
    je .drhd_duplicate_invalid
    movzx ecx, byte [r10 + SMP_DMAR_DRHD_REG_SIZE_OFF]
    mov esi, 4096
    shl rsi, cl
    add rsi, rax
    cmp r9, rsi
    jae .drhd_window_disjoint
    cmp rax, [rsp + 16]
    jb .drhd_duplicate_invalid
.drhd_window_disjoint:
    movzx eax, word [rbp + 6]
    cmp ax, [r10 + SMP_DMAR_DRHD_SEGMENT_OFF]
    jne .drhd_duplicate_next
    test byte [r10 + SMP_DMAR_DRHD_FLAGS_OFF], 1
    jnz .drhd_duplicate_invalid     ; INCLUDE_ALL must be last for a segment
.drhd_duplicate_next:
    inc edx
    jmp .drhd_duplicate_loop

.drhd_unique:
    cmp ebx, r15d
    jae .drhd_capacity_invalid
    mov eax, ebx
    imul rax, SMP_DMAR_DRHD_BYTES
    lea r10, [r14 + rax]
    mov [r10 + SMP_DMAR_DRHD_BASE_OFF], r9
    mov rax, rbp
    sub rax, r12
    mov [r10 + SMP_DMAR_DRHD_TABLE_OFFSET_OFF], eax
    mov rax, r11
    sub rax, rbp
    sub eax, 16
    mov [r10 + SMP_DMAR_DRHD_SCOPE_BYTES_OFF], eax
    mov [r10 + SMP_DMAR_DRHD_SCOPE_COUNT_OFF], r8d
    movzx eax, word [rbp + 6]
    mov [r10 + SMP_DMAR_DRHD_SEGMENT_OFF], ax
    mov al, [rbp + 4]
    mov [r10 + SMP_DMAR_DRHD_FLAGS_OFF], al
    mov al, [rbp + 5]
    mov [r10 + SMP_DMAR_DRHD_REG_SIZE_OFF], al
    inc ebx

.drhd_next_structure:
    mov rbp, r11
    jmp .drhd_structure_loop

.drhd_structures_done:
    test ebx, ebx
    jz .drhd_entry_invalid
    mov eax, ebx
    xor edx, edx
    clc
    jmp .drhd_done

.drhd_span_invalid:
    mov edx, SMP_DMAR_ERR_SPAN
    jmp .drhd_invalid
.drhd_header_invalid:
    mov edx, SMP_DMAR_ERR_HEADER
    jmp .drhd_invalid
.drhd_entry_invalid:
    mov edx, SMP_DMAR_ERR_ENTRY
    jmp .drhd_invalid
.drhd_duplicate_invalid:
    mov edx, SMP_DMAR_ERR_DUPLICATE
    jmp .drhd_invalid
.drhd_capacity_invalid:
    mov edx, SMP_DMAR_ERR_CAPACITY
.drhd_invalid:
    xor eax, eax
    stc
.drhd_done:
    lea rsp, [rsp + 24]             ; preserve the CF success/error contract
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

%endif
