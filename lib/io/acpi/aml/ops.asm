; =============================================================================
; Utkarsha OS — lib/io/acpi/aml/ops.asm
; =============================================================================
; aml_eval: one TermArg into a value. Data objects, LocalX and ArgX, names
; (methods are called), and the expression opcodes.
;
; Not built yet, reported as -AML_EUNSUPPORTED: Match, ToHexString,
; ToDecimalString, ToBCD, FromBCD, ConcatenateResTemplate, Load,
; LoadTable, and Concatenate of a string with a non-string.
; =============================================================================

%ifndef LIB_IO_ACPI_AML_OPS_ASM
%define LIB_IO_ACPI_AML_OPS_ASM

%define AML_MAX_BUFFER      0x100000    ; bytes a Buffer may ask for

section .bss
alignb 8
global aml_clock_fn
aml_clock_fn:       resq 1          ; RAX = monotonic ns (Timer)

section .text

; -----------------------------------------------------------------------------
; aml_eval — evaluate one TermArg
; Input:  RDI = destination value*
; Output: EAX = 0 or a negative AML_E* error
; -----------------------------------------------------------------------------
aml_eval:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 56                         ; A (0), B (16), R (32), spare (48)
    mov rbx, rdi
    cmp rsp, [rel aml_stack_limit]
    jb .budget
    call aml_byte
    jc .bad
    mov r12d, eax
    mov [rel aml_last_op], eax

    cmp eax, 0x00
    je .zero
    cmp eax, 0x01
    je .one
    cmp eax, 0xFF
    je .ones
    cmp eax, 0x0A
    je .byte
    cmp eax, 0x0B
    je .word
    cmp eax, 0x0C
    je .dword
    cmp eax, 0x0E
    je .qword
    cmp eax, 0x0D
    je .string
    cmp eax, 0x11
    je .buffer
    cmp eax, 0x12
    je .package
    cmp eax, 0x13
    je .varpackage
    cmp eax, 0x60
    jb .not_local
    cmp eax, 0x67
    jbe .local
    cmp eax, 0x6E
    jbe .arg
.not_local:
    call aml_is_lead
    je .name
    cmp eax, 0x5B
    je .ext
    cmp eax, 0x70
    je .store
    cmp eax, 0x71
    je .refof
    cmp eax, 0x72
    je .binop
    cmp eax, 0x73
    je .concat
    cmp eax, 0x74
    je .binop
    cmp eax, 0x75
    je .incdec
    cmp eax, 0x76
    je .incdec
    cmp eax, 0x77
    je .binop
    cmp eax, 0x78
    je .divide
    cmp eax, 0x79
    jb .unsupported
    cmp eax, 0x7F
    jbe .binop
    cmp eax, 0x80
    je .unary
    cmp eax, 0x81
    je .unary
    cmp eax, 0x82
    je .unary
    cmp eax, 0x83
    je .derefof
    cmp eax, 0x85
    je .binop
    cmp eax, 0x87
    je .sizeof
    cmp eax, 0x88
    je .index
    cmp eax, 0x8E
    je .objecttype
    cmp eax, 0x90
    je .logic2
    cmp eax, 0x91
    je .logic2
    cmp eax, 0x92
    je .lnot
    cmp eax, 0x93
    jb .unsupported
    cmp eax, 0x95
    jbe .compare
    cmp eax, 0x96
    je .tobuffer
    cmp eax, 0x99
    je .tointeger
    cmp eax, 0x9C
    je .tostring
    cmp eax, 0x9D
    je .copyobject
    cmp eax, 0x9E
    je .mid
    jmp .unsupported

; ---- data objects -----------------------------------------------------------
.zero:
    xor esi, esi
    jmp .set_int
.one:
    mov esi, 1
    jmp .set_int
.ones:
    mov rsi, -1
    jmp .set_int
.byte:
    mov edi, 1
    jmp .const
.word:
    mov edi, 2
    jmp .const
.dword:
    mov edi, 4
    jmp .const
.qword:
    mov edi, 8
.const:
    mov r13d, edi
    call aml_bytes
    jc .bad
    ; exactly the constant's bytes: it may end the table
    movzx esi, byte [rax]
    cmp r13d, 1
    je .set_int
    movzx esi, word [rax]
    cmp r13d, 2
    je .set_int
    mov esi, [rax]
    cmp r13d, 4
    je .set_int
    mov rsi, [rax]
.set_int:
    mov rdi, rbx
    call aml_set_int
    jmp .ok

.string:
    ; bytes up to a NUL inside the current list, copied
    mov r13, [r15 + aml_frame.ip]
    mov rcx, r13
.scan:
    cmp rcx, [r15 + aml_frame.end]
    jae .bad
    cmp byte [rcx], 0
    je .found
    inc rcx
    jmp .scan
.found:
    lea rax, [rcx + 1]
    mov [r15 + aml_frame.ip], rax
    sub rcx, r13
    mov r14, rcx                        ; length
    lea rdi, [rcx + 1]
    call aml_talloc
    test rax, rax
    jz .oom
    mov rdi, rax
    mov rsi, r13
    mov rcx, r14
    rep movsb
    mov qword [rbx], 0
    mov byte [rbx + aml_value.type], AML_T_STRING
    mov [rbx + aml_value.len], r14d
    mov [rbx + aml_value.data], rax
    jmp .ok

.buffer:
    ; PkgLength BufferSize ByteList: the larger of the size and the bytes
    call aml_pkglen
    jc .bad
    mov r13, rax                        ; end
    mov r14, [r15 + aml_frame.end]
    mov [r15 + aml_frame.end], r13
    call aml_eval_int
    mov [r15 + aml_frame.end], r14
    test eax, eax
    jnz .out
    mov rsi, [r15 + aml_frame.ip]
    mov rcx, r13
    sub rcx, rsi                        ; initializer bytes
    cmp rdx, rcx
    jae .bsize
    mov rdx, rcx
.bsize:
    cmp rdx, AML_MAX_BUFFER
    ja .budget
    mov [rsp + 48], rcx
    mov r14, rdx
    mov rdi, rdx
    call aml_talloc
    test rax, rax
    jz .oom
    mov rdi, rax
    mov rsi, [r15 + aml_frame.ip]
    mov rcx, [rsp + 48]
    rep movsb
    mov [r15 + aml_frame.ip], r13
    mov qword [rbx], 0
    mov byte [rbx + aml_value.type], AML_T_BUFFER
    mov [rbx + aml_value.len], r14d
    mov [rbx + aml_value.data], rax
    jmp .ok

.package:
    call aml_pkglen
    jc .bad
    mov r13, rax
    call aml_byte
    jc .bad
    mov esi, eax
    jmp .build
.varpackage:
    call aml_pkglen
    jc .bad
    mov r13, rax
    mov r14, [r15 + aml_frame.end]
    mov [r15 + aml_frame.end], r13
    call aml_eval_int
    mov [r15 + aml_frame.end], r14
    test eax, eax
    jnz .out
    cmp rdx, AML_MAX_ELEMENTS
    ja .budget
    mov esi, edx
.build:
    mov rdi, rbx
    mov rdx, r13
    call aml_build_package
    jmp .out

.local:
    sub eax, 0x60
    shl eax, 4
    lea rsi, [r15 + aml_frame.locals + rax]
    jmp .copy_slot
.arg:
    sub eax, 0x68
    shl eax, 4
    lea rsi, [r15 + aml_frame.args + rax]
.copy_slot:
    mov rdi, rbx
    call aml_copy
    jmp .out

.name:
    dec qword [r15 + aml_frame.ip]      ; the lead byte belongs to the name
    mov rdi, rbx
    call aml_eval_name
    jmp .out

; ---- extended opcodes ----------------------------------------------------------
.ext:
    call aml_byte
    jc .bad
    or eax, 0x5B00
    mov r12d, eax
    mov [rel aml_last_op], eax
    cmp eax, 0x5B30
    je .revision
    cmp eax, 0x5B31
    je .debug
    cmp eax, 0x5B33
    je .timer
    cmp eax, 0x5B12
    je .condrefof
    cmp eax, 0x5B23
    je .acquire
    cmp eax, 0x5B25
    je .wait
    jmp .unsupported
.revision:
    mov esi, 1
    jmp .set_int
.debug:
    mov qword [rbx], 0
    mov qword [rbx + 8], 0
    mov byte [rbx + aml_value.type], AML_T_DEBUG
    jmp .ok
.timer:
    ; 100 ns units
    xor esi, esi
    mov rax, [rel aml_clock_fn]
    test rax, rax
    jz .set_int
    call rax
    xor edx, edx
    mov ecx, 100
    div rcx
    mov rsi, rax
    jmp .set_int
.acquire:
    ; one fiber runs AML: every Acquire succeeds (0 = acquired)
    lea rdi, [rsp + 32]
    call aml_target
    test eax, eax
    jnz .out
    mov edi, 2
    call aml_bytes
    jc .bad
    xor esi, esi
    jmp .set_int
.wait:
    lea rdi, [rsp + 32]
    call aml_target
    test eax, eax
    jnz .out
    call aml_eval_int
    test eax, eax
    jnz .out
    xor esi, esi
    jmp .set_int
.condrefof:
    ; CondRefOf (SuperName, Target): Ones and the reference when the name
    ; exists, 0 when it does not. A missing name is not an error here.
    call aml_peek
    call aml_is_lead
    jne .condref_target
    lea rdi, [rsp]
    call aml_name
    jc .bad
    lea rdi, [rsp]
    mov rsi, [r15 + aml_frame.scope]
    call aml_resolve
    test rax, rax
    jz .condref_missing
    mov qword [rsp + 16], 0
    mov byte [rsp + 16 + aml_value.type], AML_T_REF
    mov byte [rsp + 16 + aml_value.sub], AML_REF_NODE
    mov [rsp + 16 + aml_value.data], rax
    jmp .condref_store
.condref_target:
    lea rdi, [rsp + 16]
    call aml_target
    test eax, eax
    jnz .out
.condref_store:
    lea rdi, [rsp + 32]
    call aml_target
    test eax, eax
    jnz .out
    lea rdi, [rsp + 32]
    lea rsi, [rsp + 16]
    call aml_store
    test eax, eax
    jnz .out
    mov rsi, -1
    jmp .set_int
.condref_missing:
    lea rdi, [rsp + 32]
    call aml_target                     ; the target is still in the bytecode
    test eax, eax
    jnz .out
    xor esi, esi
    jmp .set_int

; ---- Store, RefOf, CopyObject --------------------------------------------------
.store:
    lea rdi, [rsp]
    call aml_eval
    test eax, eax
    jnz .out
    lea rdi, [rsp + 32]
    call aml_target
    test eax, eax
    jnz .out
    lea rdi, [rsp + 32]
    lea rsi, [rsp]
    call aml_store
    test eax, eax
    jnz .out
.result_a:
    mov rax, [rsp]
    mov rcx, [rsp + 8]
    mov [rbx], rax
    mov [rbx + 8], rcx
    jmp .ok
.refof:
    mov rdi, rbx
    call aml_target
    jmp .out
.copyobject:
    lea rdi, [rsp]
    call aml_eval
    test eax, eax
    jnz .out
    lea rdi, [rsp + 32]
    call aml_target
    test eax, eax
    jnz .out
    mov rcx, [rsp + 32 + aml_value.data]
    movzx eax, byte [rsp + 32 + aml_value.sub]
    cmp eax, AML_REF_SLOT
    je .copy_into_slot
    cmp eax, AML_REF_NODE
    jne .type
    ; a field keeps being a field: CopyObject writes it like Store
    movzx eax, byte [rcx + aml_node.value + aml_value.type]
    cmp eax, AML_T_FIELD
    je .copy_as_store
    cmp eax, AML_T_BUFFIELD
    je .copy_as_store
    lea rdi, [rcx + aml_node.value]
    lea rsi, [rsp]
    call aml_copy
    test eax, eax
    jnz .out
    jmp .result_a
.copy_as_store:
    lea rdi, [rsp + 32]
    lea rsi, [rsp]
    call aml_store
    test eax, eax
    jnz .out
    jmp .result_a
.copy_into_slot:
    mov rdi, rcx
    lea rsi, [rsp]
    call aml_copy
    test eax, eax
    jnz .out
    jmp .result_a

; ---- integer arithmetic -------------------------------------------------------
.binop:
    call aml_eval_int
    test eax, eax
    jnz .out
    mov r13, rdx
    call aml_eval_int
    test eax, eax
    jnz .out
    mov r14, rdx
    mov rax, r13
    cmp r12d, 0x72
    je .add
    cmp r12d, 0x74
    je .sub
    cmp r12d, 0x77
    je .mul
    cmp r12d, 0x79
    je .shl
    cmp r12d, 0x7A
    je .shr
    cmp r12d, 0x7B
    je .and
    cmp r12d, 0x7C
    je .nand
    cmp r12d, 0x7D
    je .or
    cmp r12d, 0x7E
    je .nor
    cmp r12d, 0x7F
    je .xor
    ; 0x85 Mod
    test r14, r14
    jz .divzero
    xor edx, edx
    div r14
    mov rax, rdx
    jmp .int_result
.add:   add rax, r14
        jmp .int_result
.sub:   sub rax, r14
        jmp .int_result
.mul:   imul rax, r14
        jmp .int_result
.shl:
    cmp r14, 64
    jae .zero_result
    mov ecx, r14d
    shl rax, cl
    jmp .int_result
.shr:
    cmp r14, 64
    jae .zero_result
    mov ecx, r14d
    shr rax, cl
    jmp .int_result
.and:   and rax, r14
        jmp .int_result
.nand:  and rax, r14
        not rax
        jmp .int_result
.or:    or rax, r14
        jmp .int_result
.nor:   or rax, r14
        not rax
        jmp .int_result
.xor:   xor rax, r14
        jmp .int_result
.zero_result:
    xor eax, eax
.int_result:
    ; the result, then into the target if there is one
    mov rdi, rbx
    mov rsi, rax
    call aml_set_int
.to_target:
    lea rdi, [rsp + 32]
    call aml_target
    test eax, eax
    jnz .out
    lea rdi, [rsp + 32]
    mov rsi, rbx
    call aml_store
    jmp .out

.divide:
    ; Divide (Dividend, Divisor, Remainder, Result)
    call aml_eval_int
    test eax, eax
    jnz .out
    mov r13, rdx
    call aml_eval_int
    test eax, eax
    jnz .out
    test rdx, rdx
    jz .divzero
    mov r14, rdx
    mov rax, r13
    xor edx, edx
    div r14
    mov r13, rax                        ; quotient
    lea rdi, [rsp]
    mov rsi, rdx
    call aml_set_int                    ; remainder
    lea rdi, [rsp + 32]
    call aml_target
    test eax, eax
    jnz .out
    lea rdi, [rsp + 32]
    lea rsi, [rsp]
    call aml_store
    test eax, eax
    jnz .out
    mov rax, r13
    jmp .int_result

.incdec:
    lea rdi, [rsp + 32]
    call aml_target
    test eax, eax
    jnz .out
    lea rdi, [rsp + 32]
    lea rsi, [rsp]
    call aml_ref_read
    test eax, eax
    jnz .out
    lea rdi, [rsp]
    xor esi, esi
    call aml_to_int
    test eax, eax
    jnz .out
    mov rax, rdx
    inc rax
    cmp r12d, 0x75
    je .incdec_set
    sub rax, 2
.incdec_set:
    mov rdi, rbx
    mov rsi, rax
    call aml_set_int
    lea rdi, [rsp + 32]
    mov rsi, rbx
    call aml_store
    jmp .out

.unary:
    call aml_eval_int
    test eax, eax
    jnz .out
    mov rax, rdx
    cmp r12d, 0x80
    je .not
    and rdx, [rel aml_int_ones]
    xor eax, eax
    test rdx, rdx
    jz .int_result                      ; no bit set: 0
    cmp r12d, 0x81
    je .left
    bsf rax, rdx
    inc rax
    jmp .int_result
.left:
    bsr rax, rdx
    inc rax
    jmp .int_result
.not:
    not rax
    jmp .int_result

; ---- logic and comparison -----------------------------------------------------
.logic2:
    call aml_eval_int
    test eax, eax
    jnz .out
    mov r13, rdx
    call aml_eval_int
    test eax, eax
    jnz .out
    xor esi, esi
    cmp r12d, 0x90
    je .land
    or rdx, r13
    jz .set_int
    jmp .true
.land:
    test r13, r13
    jz .set_int
    test rdx, rdx
    jz .set_int
.true:
    mov rsi, -1
    jmp .set_int

.lnot:
    call aml_peek
    cmp eax, 0x93
    jb .lnot_plain
    cmp eax, 0x95
    ja .lnot_plain
    ; LNotEqual, LLessEqual, LGreaterEqual: the comparison, inverted
    mov r12d, eax
    call aml_byte
    call aml_compare_ops
    test eax, eax
    jnz .out
    xor esi, esi
    test ecx, ecx
    jnz .set_int
    jmp .true
.lnot_plain:
    call aml_eval_int
    test eax, eax
    jnz .out
    xor esi, esi
    test rdx, rdx
    jnz .set_int
    jmp .true

.compare:
    call aml_compare_ops
    test eax, eax
    jnz .out
    xor esi, esi
    test ecx, ecx
    jz .set_int
    jmp .true

; ---- objects -----------------------------------------------------------------------
.derefof:
    lea rdi, [rsp]
    call aml_eval
    test eax, eax
    jnz .out
    cmp byte [rsp + aml_value.type], AML_T_REF
    jne .type
    lea rdi, [rsp]
    mov rsi, rbx
    call aml_ref_read
    jmp .out

.sizeof:
    call aml_slot
    test eax, eax
    jnz .out
    movzx eax, byte [rdx + aml_value.type]
    cmp eax, AML_T_STRING
    je .size
    cmp eax, AML_T_BUFFER
    je .size
    cmp eax, AML_T_PACKAGE
    jne .type
.size:
    mov esi, [rdx + aml_value.len]
    jmp .set_int

.index:
    ; Index (BuffPkgStrObj, Index, Target): a reference to one element
    call aml_slot
    test eax, eax
    jnz .out
    mov r13, rdx
    call aml_eval_int
    test eax, eax
    jnz .out
    mov eax, [r13 + aml_value.len]
    cmp rdx, rax
    jae .index_out
    mov qword [rbx], 0
    mov byte [rbx + aml_value.type], AML_T_REF
    movzx eax, byte [r13 + aml_value.type]
    mov rcx, [r13 + aml_value.data]
    cmp eax, AML_T_PACKAGE
    je .index_pkg
    cmp eax, AML_T_BUFFER
    je .index_byte
    cmp eax, AML_T_STRING
    je .index_byte
    jmp .type
.index_pkg:
    shl rdx, 4
    add rcx, rdx
    mov byte [rbx + aml_value.sub], AML_REF_SLOT
    mov [rbx + aml_value.data], rcx
    jmp .to_target
.index_byte:
    add rcx, rdx
    mov byte [rbx + aml_value.sub], AML_REF_BYTE
    mov [rbx + aml_value.data], rcx
    jmp .to_target
.index_out:
    mov eax, -AML_EINDEX
    jmp .out

.objecttype:
    lea rdi, [rsp + 32]
    call aml_target
    test eax, eax
    jnz .out
    movzx eax, byte [rsp + 32 + aml_value.sub]
    mov rcx, [rsp + 32 + aml_value.data]
    mov esi, AML_T_DEBUG
    cmp eax, AML_REF_DEBUG
    je .set_int
    xor esi, esi
    cmp eax, AML_REF_SLOT
    je .type_slot
    cmp eax, AML_REF_NODE
    jne .set_int
    lea rcx, [rcx + aml_node.value]
.type_slot:
    movzx esi, byte [rcx + aml_value.type]
    cmp esi, AML_T_REF                  ; a stored reference to an object:
    jne .type_known                     ; the object's type
    cmp byte [rcx + aml_value.sub], AML_REF_NODE
    jne .type_known
    mov rcx, [rcx + aml_value.data]
    movzx esi, byte [rcx + aml_node.value + aml_value.type]
.type_known:
    cmp esi, AML_T_DEBUG
    jbe .set_int
    xor esi, esi                        ; internal kinds read as 0
    jmp .set_int

; ---- conversions -----------------------------------------------------------------
.tointeger:
    lea rdi, [rsp]
    call aml_eval
    test eax, eax
    jnz .out
    lea rdi, [rsp]
    mov esi, 1
    call aml_to_int
    test eax, eax
    jnz .out
    mov rax, rdx
    jmp .int_result

.tobuffer:
    lea rdi, [rsp]
    call aml_eval
    test eax, eax
    jnz .out
    mov rdi, rbx
    lea rsi, [rsp]
    call aml_to_buffer
    test eax, eax
    jnz .out
    jmp .to_target

.tostring:
    ; ToString (Buffer, Length, Target): bytes up to a NUL or Length
    lea rdi, [rsp]
    call aml_eval
    test eax, eax
    jnz .out
    call aml_eval_int
    test eax, eax
    jnz .out
    cmp byte [rsp + aml_value.type], AML_T_BUFFER
    jne .type
    mov rsi, [rsp + aml_value.data]
    mov ecx, [rsp + aml_value.len]
    cmp rdx, rcx
    jae .ts_scan
    mov ecx, edx
.ts_scan:
    xor r13d, r13d
.ts_next:
    cmp r13d, ecx
    jae .ts_len
    cmp byte [rsi + r13], 0
    je .ts_len
    inc r13d
    jmp .ts_next
.ts_len:
    lea rdi, [r13 + 1]
    call aml_talloc
    test rax, rax
    jz .oom
    mov rdi, rax
    mov rsi, [rsp + aml_value.data]
    mov ecx, r13d
    rep movsb
    mov qword [rbx], 0
    mov byte [rbx + aml_value.type], AML_T_STRING
    mov [rbx + aml_value.len], r13d
    mov [rbx + aml_value.data], rax
    jmp .to_target

.concat:
    ; Concatenate (Source1, Source2, Target), by Source1's type
    lea rdi, [rsp]
    call aml_eval
    test eax, eax
    jnz .out
    lea rdi, [rsp + 16]
    call aml_eval
    test eax, eax
    jnz .out
    movzx eax, byte [rsp + aml_value.type]
    cmp eax, AML_T_STRING
    je .concat_strings
    ; integers and buffers: both as buffers, end to end
    lea rdi, [rsp]
    lea rsi, [rsp]
    call aml_to_buffer
    test eax, eax
    jnz .out
    cmp byte [rsp + 16 + aml_value.type], AML_T_INTEGER
    jne .concat_b2
    ; an integer after an integer: both at the integer width
.concat_b2:
    lea rdi, [rsp + 16]
    lea rsi, [rsp + 16]
    call aml_to_buffer
    test eax, eax
    jnz .out
    mov r13d, AML_T_BUFFER
    xor r14d, r14d                      ; no NUL
    jmp .concat_join
.concat_strings:
    cmp byte [rsp + 16 + aml_value.type], AML_T_STRING
    jne .unsupported
    mov r13d, AML_T_STRING
    mov r14d, 1
.concat_join:
    mov ecx, [rsp + aml_value.len]
    add ecx, [rsp + 16 + aml_value.len]
    mov [rsp + 48], ecx
    lea edi, [rcx + r14]
    call aml_talloc
    test rax, rax
    jz .oom
    mov rdi, rax
    mov rsi, [rsp + aml_value.data]
    mov ecx, [rsp + aml_value.len]
    rep movsb
    mov rsi, [rsp + 16 + aml_value.data]
    mov ecx, [rsp + 16 + aml_value.len]
    rep movsb
    mov qword [rbx], 0
    mov [rbx + aml_value.type], r13b
    mov ecx, [rsp + 48]
    mov [rbx + aml_value.len], ecx
    mov [rbx + aml_value.data], rax
    jmp .to_target

.mid:
    ; Mid (Source, Index, Length, Target): part of a string or buffer
    lea rdi, [rsp]
    call aml_eval
    test eax, eax
    jnz .out
    call aml_eval_int
    test eax, eax
    jnz .out
    mov r13, rdx                        ; index
    call aml_eval_int
    test eax, eax
    jnz .out
    mov r14, rdx                        ; length
    movzx eax, byte [rsp + aml_value.type]
    cmp eax, AML_T_STRING
    je .mid_ok
    cmp eax, AML_T_BUFFER
    jne .type
.mid_ok:
    mov ecx, [rsp + aml_value.len]
    cmp r13, rcx
    jbe .mid_start
    mov r13, rcx
.mid_start:
    sub rcx, r13                        ; bytes left after Index
    cmp r14, rcx
    jbe .mid_len
    mov r14, rcx
.mid_len:
    lea rdi, [r14 + 1]
    call aml_talloc
    test rax, rax
    jz .oom
    mov rdi, rax
    mov rsi, [rsp + aml_value.data]
    add rsi, r13
    mov rcx, r14
    rep movsb
    movzx ecx, byte [rsp + aml_value.type]
    mov qword [rbx], 0
    mov [rbx + aml_value.type], cl
    mov [rbx + aml_value.len], r14d
    mov [rbx + aml_value.data], rax
    jmp .to_target

; ---- endings ----------------------------------------------------------------------
.ok:
    xor eax, eax
    jmp .out
.type:
    mov eax, -AML_ETYPE
    jmp .out
.divzero:
    mov eax, -AML_EDIVZERO
    jmp .out
.oom:
    mov eax, -AML_ENOMEM
    jmp .out
.budget:
    mov eax, -AML_EBUDGET
    jmp .out
.unsupported:
    mov eax, -AML_EUNSUPPORTED
    jmp .out
.bad:
    mov eax, -AML_EBADCODE
.out:
    add rsp, 56
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_compare_ops — read two operands and compare them for the opcode in
;                   R12D (0x93 LEqual, 0x94 LGreater, 0x95 LLess)
; Output: EAX = 0 or error; ECX = 1 when the comparison holds, else 0
; -----------------------------------------------------------------------------
aml_compare_ops:
    push rbx
    sub rsp, 32
    lea rdi, [rsp]
    call aml_eval
    test eax, eax
    jnz .out
    lea rdi, [rsp + 16]
    call aml_eval
    test eax, eax
    jnz .out
    lea rdi, [rsp]
    lea rsi, [rsp + 16]
    call aml_compare
    test eax, eax
    jnz .out
    xor ecx, ecx
    cmp r12d, 0x93
    je .eq
    cmp r12d, 0x94
    je .gt
    cmp edx, -1                         ; LLess
    sete cl
    jmp .out
.eq:
    test edx, edx
    sete cl
    jmp .out
.gt:
    cmp edx, 1
    sete cl
.out:
    add rsp, 32
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_build_package — read package elements up to RDX
; Input:  RDI = destination value*, ESI = element count, RDX = end
; Names inside a package become references to their objects, or stay
; unresolved names when nothing by that name exists yet.
; -----------------------------------------------------------------------------
aml_build_package:
    push rbx
    push r12
    push r13
    push r14
    push rbp
    sub rsp, 48                         ; element, index, path (16), name start
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov edi, esi
    shl rdi, 4
    call aml_talloc
    test rax, rax
    jnz .have
    test r12d, r12d
    jnz .oom
.have:
    mov r14, rax
    mov rbp, [r15 + aml_frame.end]
    mov [r15 + aml_frame.end], r13
    xor ecx, ecx
.elem:
    cmp ecx, r12d
    jae .done
    mov rax, [r15 + aml_frame.ip]
    cmp rax, r13
    jae .done
    mov [rsp + 8], rcx
    shl ecx, 4
    lea rdi, [r14 + rcx]
    mov [rsp], rdi
    call aml_peek
    call aml_is_lead
    je .name
    mov rdi, [rsp]
    call aml_eval
    test eax, eax
    jnz .fail
    jmp .next
.name:
    mov rax, [r15 + aml_frame.ip]
    mov [rsp + 32], rax
    lea rdi, [rsp + 16]
    call aml_name
    jc .bad
    lea rdi, [rsp + 16]
    mov rsi, [r15 + aml_frame.scope]
    call aml_resolve
    mov rdi, [rsp]
    mov qword [rdi], 0
    mov qword [rdi + 8], 0
    test rax, rax
    jz .unresolved
    mov byte [rdi + aml_value.type], AML_T_REF
    mov byte [rdi + aml_value.sub], AML_REF_NODE
    mov [rdi + aml_value.data], rax
    jmp .next
.unresolved:
    mov byte [rdi + aml_value.type], AML_T_NAMEREF
    mov rax, [rsp + 32]
    mov [rdi + aml_value.data], rax
.next:
    mov rcx, [rsp + 8]
    inc ecx
    jmp .elem
.done:
    mov [r15 + aml_frame.end], rbp
    mov [r15 + aml_frame.ip], r13       ; extra initializers are ignored
    mov qword [rbx], 0
    mov byte [rbx + aml_value.type], AML_T_PACKAGE
    mov [rbx + aml_value.len], r12d
    mov [rbx + aml_value.data], r14
    xor eax, eax
    jmp .out
.bad:
    mov eax, -AML_EBADCODE
.fail:
    mov [r15 + aml_frame.end], rbp
    jmp .out
.oom:
    mov eax, -AML_ENOMEM
.out:
    add rsp, 48
    pop rbp
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_IO_ACPI_AML_OPS_ASM
