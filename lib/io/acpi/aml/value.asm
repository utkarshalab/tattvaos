; =============================================================================
; Utkarsha OS — lib/io/acpi/aml/value.asm
; =============================================================================
; Values: deep copies, conversions and comparison.
;
; Where a copy lives follows from where it goes: a destination inside the
; permanent part of the heap (a named object that outlives the evaluation)
; gets permanent memory, anything else gets temporary memory.
; =============================================================================

%ifndef LIB_IO_ACPI_AML_VALUE_ASM
%define LIB_IO_ACPI_AML_VALUE_ASM

section .data
align 8
aml_int_ones:       dq -1           ; all ones at the table's integer width
aml_int_bytes:      dd 8            ; 4 for tables of revision 1

section .text

; -----------------------------------------------------------------------------
; aml_mask — cut RAX to the integer width
; -----------------------------------------------------------------------------
aml_mask:
    and rax, [rel aml_int_ones]
    ret

; -----------------------------------------------------------------------------
; aml_is_perm — whether an address is in permanent memory
; Input:  RDI = address
; Output: ZF = 0 (jnz) when permanent
; Clobbers: RAX
; -----------------------------------------------------------------------------
aml_is_perm:
    xor eax, eax
    cmp rdi, [rel aml_heap_base]
    jb .no
    cmp rdi, [rel aml_heap_perm]
    jae .no
    inc eax
.no:
    test eax, eax
    ret

; -----------------------------------------------------------------------------
; aml_mem_for — allocate for a destination
; Input:  RDI = bytes, RSI = the destination (decides permanent or temporary)
; Output: RAX = memory or 0
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
aml_mem_for:
    push rdi
    mov rdi, rsi
    call aml_is_perm
    pop rdi
    jnz aml_alloc
    jmp aml_talloc

; -----------------------------------------------------------------------------
; aml_set_int — store an integer into a value
; Input:  RDI = value*, RSI = integer (cut to the width)
; Clobbers: RAX
; -----------------------------------------------------------------------------
aml_set_int:
    mov rax, rsi
    and rax, [rel aml_int_ones]
    mov qword [rdi], 0
    mov byte [rdi + aml_value.type], AML_T_INTEGER
    mov [rdi + aml_value.data], rax
    ret

; -----------------------------------------------------------------------------
; aml_copy — deep copy of a value
; Input:  RDI = destination value*, RSI = source value*
; Output: EAX = 0 or -AML_ENOMEM
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
aml_copy:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12, rsi
    ; the plain 16 bytes first; source and destination may be the same
    mov rax, [r12]
    mov rcx, [r12 + 8]
    mov [rbx], rax
    mov [rbx + 8], rcx
    movzx eax, byte [rbx + aml_value.type]
    cmp eax, AML_T_STRING
    je .bytes1
    cmp eax, AML_T_BUFFER
    je .bytes0
    cmp eax, AML_T_PACKAGE
    je .package
    xor eax, eax
    jmp .out
.bytes1:
    mov r14d, 1                         ; strings keep a NUL after them
    jmp .bytes
.bytes0:
    xor r14d, r14d
.bytes:
    mov r13d, [rbx + aml_value.len]
    lea rdi, [r13 + r14]
    mov rsi, rbx
    call aml_mem_for
    test rax, rax
    jz .oom
    mov rsi, [rbx + aml_value.data]
    mov rdi, rax
    mov [rbx + aml_value.data], rax
    mov ecx, r13d
    rep movsb
    xor eax, eax
    jmp .out
.package:
    mov r13d, [rbx + aml_value.len]
    mov rdi, r13
    shl rdi, 4
    mov rsi, rbx
    call aml_mem_for
    test rax, rax
    jz .oom
    mov r14, [rbx + aml_value.data]     ; source elements
    mov [rbx + aml_value.data], rax
    mov r15, rax
.elem:
    test r13d, r13d
    jz .done
    mov rdi, r15
    mov rsi, r14
    call aml_copy
    test eax, eax
    jnz .out
    add r15, aml_value_size
    add r14, aml_value_size
    dec r13d
    jmp .elem
.done:
    xor eax, eax
    jmp .out
.oom:
    mov eax, -AML_ENOMEM
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_to_int — a value as an integer (implicit conversion)
; Input:  RDI = value*, ESI = 1 for ToInteger rules (decimal unless 0x),
;         0 for implicit rules (hexadecimal)
; Output: EAX = 0 or -AML_ETYPE; RDX = the integer
; Clobbers: RAX, RCX, RDX, RSI, R8, R9
; -----------------------------------------------------------------------------
aml_to_int:
    movzx eax, byte [rdi + aml_value.type]
    cmp eax, AML_T_INTEGER
    je .int
    cmp eax, AML_T_BUFFER
    je .buffer
    cmp eax, AML_T_STRING
    je .string
    mov eax, -AML_ETYPE
    xor edx, edx
    ret
.int:
    mov rdx, [rdi + aml_value.data]
    xor eax, eax
    ret
.buffer:
    ; little-endian, at most the integer width
    mov ecx, [rdi + aml_value.len]
    cmp ecx, [rel aml_int_bytes]
    jbe .blen
    mov ecx, [rel aml_int_bytes]
.blen:
    mov r8, [rdi + aml_value.data]
    xor edx, edx
.bbyte:
    test ecx, ecx
    jz .bdone
    dec ecx
    shl rdx, 8
    movzx eax, byte [r8 + rcx]
    or rdx, rax
    jmp .bbyte
.bdone:
    xor eax, eax
    ret
.string:
    mov r8, [rdi + aml_value.data]
    mov ecx, [rdi + aml_value.len]
    xor edx, edx
    mov r9d, 16                         ; base
    test esi, esi
    jz .digits
    mov r9d, 10
    cmp ecx, 2
    jb .digits
    cmp byte [r8], '0'
    jne .digits
    mov al, [r8 + 1]
    or al, 0x20
    cmp al, 'x'
    jne .digits
    mov r9d, 16
    add r8, 2
    sub ecx, 2
.digits:
    test ecx, ecx
    jz .sdone
    movzx eax, byte [r8]
    sub eax, '0'
    cmp eax, 9
    jbe .digit
    movzx eax, byte [r8]
    or eax, 0x20
    sub eax, 'a'
    cmp eax, 5
    ja .sdone                           ; stops at the first non-digit
    add eax, 10
.digit:
    cmp eax, r9d
    jae .sdone
    imul rdx, r9
    add rdx, rax
    inc r8
    dec ecx
    jmp .digits
.sdone:
    and rdx, [rel aml_int_ones]
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; aml_to_buffer — a value as a buffer (temporary memory)
; Input:  RDI = destination value*, RSI = source value*
;         Integer: its bytes at the integer width. String: its bytes and the
;         NUL. Buffer: a copy.
; Output: EAX = 0, -AML_ETYPE or -AML_ENOMEM
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
aml_to_buffer:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    movzx eax, byte [r12 + aml_value.type]
    cmp eax, AML_T_INTEGER
    je .int
    cmp eax, AML_T_STRING
    je .string
    cmp eax, AML_T_BUFFER
    je .buffer
    mov eax, -AML_ETYPE
    jmp .out
.int:
    mov r13, [r12 + aml_value.data]
    mov edi, 8
    call aml_talloc
    test rax, rax
    jz .oom
    mov [rax], r13
    mov qword [rbx], 0
    mov byte [rbx + aml_value.type], AML_T_BUFFER
    mov ecx, [rel aml_int_bytes]
    mov [rbx + aml_value.len], ecx
    mov [rbx + aml_value.data], rax
    xor eax, eax
    jmp .out
.string:
    mov r13d, [r12 + aml_value.len]
    lea edi, [r13 + 1]
    call aml_talloc
    test rax, rax
    jz .oom
    mov rdi, rax
    mov rsi, [r12 + aml_value.data]
    mov ecx, r13d
    rep movsb                           ; the NUL is already there
    mov qword [rbx], 0
    mov byte [rbx + aml_value.type], AML_T_BUFFER
    lea ecx, [r13 + 1]
    mov [rbx + aml_value.len], ecx
    mov [rbx + aml_value.data], rax
    xor eax, eax
    jmp .out
.buffer:
    mov rdi, rbx
    mov rsi, r12
    call aml_copy
    jmp .out
.oom:
    mov eax, -AML_ENOMEM
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_compare — compare two values the way LEqual, LLess and LGreater do:
;               by the first one's type, converting the second
; Input:  RDI = first, RSI = second
; Output: EAX = 0 or a negative error; EDX = -1, 0 or 1
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
aml_compare:
    push rbx
    push r12
    push r13
    sub rsp, 16                         ; a converted second operand
    mov rbx, rdi
    mov r12, rsi
    movzx eax, byte [rbx + aml_value.type]
    cmp eax, AML_T_INTEGER
    je .ints
    cmp eax, AML_T_STRING
    je .bytes
    cmp eax, AML_T_BUFFER
    je .as_buffer
    mov eax, -AML_ETYPE
    jmp .out
.ints:
    mov rdi, r12
    xor esi, esi
    call aml_to_int
    test eax, eax
    jnz .out
    mov rax, [rbx + aml_value.data]
    xor ecx, ecx
    cmp rax, rdx
    je .result
    mov ecx, 1
    ja .result
    mov ecx, -1
    jmp .result
.as_buffer:
    cmp byte [r12 + aml_value.type], AML_T_BUFFER
    je .bytes
    mov rdi, rsp
    mov rsi, r12
    call aml_to_buffer
    test eax, eax
    jnz .out
    mov r12, rsp
.bytes:
    ; a string compares with a string; byte by byte, then by length
    movzx eax, byte [r12 + aml_value.type]
    cmp al, [rbx + aml_value.type]
    jne .type
    mov rsi, [rbx + aml_value.data]
    mov rdi, [r12 + aml_value.data]
    mov r8d, [rbx + aml_value.len]
    mov r9d, [r12 + aml_value.len]
    mov r13d, r8d
    cmp r13d, r9d
    jbe .n
    mov r13d, r9d
.n:
    xor ecx, ecx
.cmp:
    cmp ecx, r13d
    jae .lengths
    movzx eax, byte [rsi + rcx]
    movzx edx, byte [rdi + rcx]
    inc ecx
    cmp eax, edx
    je .cmp
    mov ecx, 1
    ja .result
    mov ecx, -1
    jmp .result
.lengths:
    xor ecx, ecx
    cmp r8d, r9d
    je .result
    mov ecx, 1
    ja .result
    mov ecx, -1
.result:
    mov edx, ecx
    xor eax, eax
    jmp .out
.type:
    mov eax, -AML_ETYPE
.out:
    add rsp, 16
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_IO_ACPI_AML_VALUE_ASM
