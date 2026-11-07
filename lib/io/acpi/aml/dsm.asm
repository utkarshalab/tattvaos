; =============================================================================
; Utkarsha OS — lib/io/acpi/aml/dsm.asm
; =============================================================================
; _DSM, the device-specific method: one method per device, selected by a
; UUID, a revision and a function number, with a package of arguments.
;
;   aml_dsm(node, uuid, revision, function, value*)   call it
;   aml_dsm_supported(node, uuid, revision, function) whether the device
;       implements that function: function 0 returns a buffer whose bit N
;       is set for each function N it has (bit 0: any at all)
;
; The UUID is 16 bytes in the order _DSM compares them (the ToUUID byte
; order: the first three groups little-endian). Arguments for the
; function are an empty package; functions that need some are called
; through aml_eval_path.
; =============================================================================

%ifndef LIB_IO_ACPI_AML_DSM_ASM
%define LIB_IO_ACPI_AML_DSM_ASM

section .text

; -----------------------------------------------------------------------------
; aml_dsm — call a device's _DSM
; Input:  RDI = device node, RSI = UUID (16 bytes), EDX = revision,
;         ECX = function, R8 = destination value*
; Output: EAX = 0; -AML_ENOTFOUND without _DSM; or an error from running it
; -----------------------------------------------------------------------------
global aml_dsm
aml_dsm:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    mov rbp, r8
    AML_BEGIN
    call aml_top_frame
    test rax, rax
    jz .oom
    mov r15, rax
    mov rdi, rbx
    mov esi, AML_SEG('_','D','S','M')
    call aml_child
    test rax, rax
    jz .missing
    cmp byte [rax + aml_node.value + aml_value.type], AML_T_METHOD
    jne .missing
    mov rbx, rax
    ; arguments: Buffer (UUID), revision, function, empty package
    mov edi, AML_ARGS * aml_value_size + 16
    call aml_talloc
    test rax, rax
    jz .oom
    lea rcx, [rax + AML_ARGS * aml_value_size]   ; the UUID's copy
    mov rdx, [r12]
    mov [rcx], rdx
    mov rdx, [r12 + 8]
    mov [rcx + 8], rdx
    mov byte [rax + aml_value.type], AML_T_BUFFER
    mov dword [rax + aml_value.len], 16
    mov [rax + aml_value.data], rcx
    mov byte [rax + 16 + aml_value.type], AML_T_INTEGER
    mov [rax + 16 + aml_value.data], r13
    mov byte [rax + 32 + aml_value.type], AML_T_INTEGER
    mov [rax + 32 + aml_value.data], r14
    mov byte [rax + 48 + aml_value.type], AML_T_PACKAGE
    mov rdi, rbx
    mov rsi, rax
    mov rdx, rbp
    call aml_call
    jmp .out
.missing:
    mov eax, -AML_ENOTFOUND
    jmp .out
.oom:
    mov eax, -AML_ENOMEM
.out:
    add rsp, 8
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_dsm_supported — whether a _DSM function exists
; Input:  RDI = device node, RSI = UUID, EDX = revision, ECX = function
; Output: EAX = 1 when function 0 lists it (and lists anything), else 0
; -----------------------------------------------------------------------------
global aml_dsm_supported
aml_dsm_supported:
    push rbx
    sub rsp, 16
    mov ebx, ecx
    xor ecx, ecx                        ; function 0: what is supported
    mov r8, rsp
    call aml_dsm
    test eax, eax
    jnz .no
    ; a buffer, or (some firmware) an integer
    movzx eax, byte [rsp + aml_value.type]
    cmp eax, AML_T_INTEGER
    je .integer
    cmp eax, AML_T_BUFFER
    jne .no
    mov rsi, [rsp + aml_value.data]
    mov ecx, [rsp + aml_value.len]
    test ecx, ecx
    jz .no
    test byte [rsi], 1                  ; bit 0: anything at all
    jz .no
    mov eax, ebx
    shr eax, 3                          ; the byte with bit N
    cmp eax, ecx
    jae .no
    movzx edx, byte [rsi + rax]
    mov ecx, ebx
    and ecx, 7
    bt edx, ecx
    jnc .no
    jmp .yes
.integer:
    mov rdx, [rsp + aml_value.data]
    test edx, 1
    jz .no
    cmp ebx, 64
    jae .no
    bt rdx, rbx
    jnc .no
.yes:
    mov eax, 1
    jmp .out
.no:
    xor eax, eax
.out:
    add rsp, 16
    pop rbx
    ret

%endif ; LIB_IO_ACPI_AML_DSM_ASM
