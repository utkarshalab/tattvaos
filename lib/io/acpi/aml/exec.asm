; =============================================================================
; Utkarsha OS — lib/io/acpi/aml/exec.asm
; =============================================================================
; Running term lists: statements (If, While, Return, ...), the operators
; that define named objects (Name, Scope, Device, Method, OperationRegion,
; Field, ...), method calls, reading names, targets and Store.
;
; R15 = the current frame. Every function returns EAX = 0 or a negative
; AML_E* error, which stops the method and everything that called it.
; =============================================================================

%ifndef LIB_IO_ACPI_AML_EXEC_ASM
%define LIB_IO_ACPI_AML_EXEC_ASM

section .bss
alignb 8
aml_stack_limit:    resq 1          ; lowest RSP the interpreter may reach
global aml_notify_fn
aml_notify_fn:      resq 1          ; RDI = node, RSI = value
global aml_debug_fn
aml_debug_fn:       resq 1          ; RDI = value* stored to Debug
global aml_sleep_fn
aml_sleep_fn:       resq 1          ; RDI = nanoseconds (Sleep and Stall)
global aml_loops
aml_loops:          resd 1          ; While iterations this evaluation
global aml_dup_names
aml_dup_names:      resd 1          ; names defined twice (the second skipped)
global aml_last_op
aml_last_op:        resd 1          ; the opcode being run, for diagnostics

section .text

; -----------------------------------------------------------------------------
; aml_run_list — run terms until the end of the list, an error, or a
;                Return, Break or Continue
; -----------------------------------------------------------------------------
aml_run_list:
    sub rsp, 8
.loop:
    cmp dword [r15 + aml_frame.flags], 0
    jne .ok
    mov rax, [r15 + aml_frame.ip]
    cmp rax, [r15 + aml_frame.end]
    jae .ok
    call aml_exec_term
    test eax, eax
    jz .loop
    jmp .out
.ok:
    xor eax, eax
.out:
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; aml_run_block — run the term list from IP to RDI, then continue at RDI
; -----------------------------------------------------------------------------
aml_run_block:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, [r15 + aml_frame.end]
    mov [r15 + aml_frame.end], rbx
    call aml_run_list
    mov [r15 + aml_frame.end], r12
    mov [r15 + aml_frame.ip], rbx
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_eval_int — evaluate a TermArg as an integer
; Output: EAX = 0 or error; RDX = the integer
; -----------------------------------------------------------------------------
aml_eval_int:
    sub rsp, 24
    mov rdi, rsp
    call aml_eval
    test eax, eax
    jnz .out
    mov rdi, rsp
    xor esi, esi
    call aml_to_int
.out:
    add rsp, 24
    ret

; -----------------------------------------------------------------------------
; aml_exec_term — run one term
; -----------------------------------------------------------------------------
aml_exec_term:
    push rbx
    sub rsp, 16                         ; the result of a bare expression
    call aml_peek
    mov [rel aml_last_op], eax
    cmp eax, 0x08
    je .name
    cmp eax, 0x10
    je .scope
    cmp eax, 0x14
    je .method
    cmp eax, 0x06
    je .alias
    cmp eax, 0x15
    je .external
    cmp eax, 0xA0
    je .if
    cmp eax, 0xA1
    je .else
    cmp eax, 0xA2
    je .while
    cmp eax, 0xA3
    je .skip1                           ; Noop
    cmp eax, 0xCC
    je .skip1                           ; BreakPoint
    cmp eax, 0xA4
    je .return
    cmp eax, 0xA5
    je .break
    cmp eax, 0x9F
    je .continue
    cmp eax, 0x86
    je .notify
    cmp eax, 0x8A
    jb .not_create
    cmp eax, 0x8D
    jbe .create
    cmp eax, 0x8F
    je .create
.not_create:
    cmp eax, 0x5B
    jne .expression
    ; extended opcodes
    mov rcx, [r15 + aml_frame.ip]
    lea rdx, [rcx + 1]
    cmp rdx, [r15 + aml_frame.end]
    jae .bad
    movzx eax, byte [rcx + 1]
    or eax, 0x5B00
    mov [rel aml_last_op], eax
    cmp eax, 0x5B80
    je .region
    cmp eax, 0x5B81
    je .field
    cmp eax, 0x5B86
    je .field
    cmp eax, 0x5B87
    je .field
    cmp eax, 0x5B82
    je .device
    cmp eax, 0x5B83
    je .device
    cmp eax, 0x5B84
    je .device
    cmp eax, 0x5B85
    je .device
    cmp eax, 0x5B01
    je .mutex
    cmp eax, 0x5B02
    je .event
    cmp eax, 0x5B13
    je .create
    cmp eax, 0x5B22
    je .sleep
    cmp eax, 0x5B21
    je .sleep
    cmp eax, 0x5B27
    je .release
    cmp eax, 0x5B24
    je .release
    cmp eax, 0x5B26
    je .release
    cmp eax, 0x5B32
    je .fatal
.expression:
    mov rdi, rsp
    call aml_eval
    jmp .out
.name:      call aml_op_name
            jmp .out
.scope:     call aml_op_scope
            jmp .out
.method:    call aml_op_method
            jmp .out
.alias:     call aml_op_alias
            jmp .out
.external:  call aml_op_external
            jmp .out
.if:        call aml_op_if
            jmp .out
.else:      call aml_op_else
            jmp .out
.while:     call aml_op_while
            jmp .out
.return:    call aml_op_return
            jmp .out
.break:
    call aml_byte
    or dword [r15 + aml_frame.flags], AML_F_BREAK
    xor eax, eax
    jmp .out
.continue:
    call aml_byte
    or dword [r15 + aml_frame.flags], AML_F_CONTINUE
    xor eax, eax
    jmp .out
.skip1:
    call aml_byte
    xor eax, eax
    jmp .out
.notify:    call aml_op_notify
            jmp .out
.create:    call aml_op_create_field
            jmp .out
.region:    call aml_op_region
            jmp .out
.field:     call aml_op_field
            jmp .out
.device:    call aml_op_device
            jmp .out
.mutex:
.event:     call aml_op_sync_object
            jmp .out
.sleep:     call aml_op_sleep
            jmp .out
.release:   call aml_op_release
            jmp .out
.fatal:
    mov eax, -AML_EFATAL
    jmp .out
.bad:
    mov eax, -AML_EBADCODE
.out:
    add rsp, 16
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_new_named — create the node a path names, in the current scope
; Inside a running method the node is temporary (see aml_node_new).
; A node declared by External is taken over by its real definition.
; Input:  RDI = aml_path*, ESI = type
; Output: RAX = node, or 0 (missing parent, out of memory);
;         EDX = 1 when a real definition existed already
; -----------------------------------------------------------------------------
aml_new_named:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, esi
    cmp qword [r15 + aml_frame.method], 0
    je .create
    mov [rel aml_node_frame], r15
.create:
    mov rsi, [r15 + aml_frame.scope]
    call aml_create
    mov qword [rel aml_node_frame], 0
    test rax, rax
    jz .out
    mov rbx, rax
    test edx, edx
    jz .fresh
    test dword [rbx + aml_node.flags], AML_NODE_EXTERNAL
    jz .existed
    and dword [rbx + aml_node.flags], ~AML_NODE_EXTERNAL
.fresh:
    mov [rbx + aml_node.value + aml_value.type], r12b
    xor edx, edx
    mov rax, rbx
    jmp .out
.existed:
    mov rax, rbx
    mov edx, 1
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Name (0x08): NameString DataRefObject
; -----------------------------------------------------------------------------
aml_op_name:
    push rbx
    push r12
    sub rsp, 40                         ; path (16), value (16), pad
    call aml_byte
    mov rdi, rsp
    call aml_name
    jc .bad
    lea rdi, [rsp + 16]
    call aml_eval
    test eax, eax
    jnz .out
    mov rdi, rsp
    mov esi, AML_T_UNINIT
    call aml_new_named
    test rax, rax
    jz .nomem
    test edx, edx
    jnz .dup
    lea rdi, [rax + aml_node.value]
    lea rsi, [rsp + 16]
    call aml_copy
    jmp .out
.dup:
    inc dword [rel aml_dup_names]
    xor eax, eax
    jmp .out
.nomem:
    call aml_err_missing
    jmp .out
.bad:
    mov eax, -AML_EBADCODE
.out:
    add rsp, 40
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Scope (0x10): PkgLength NameString TermList
; -----------------------------------------------------------------------------
aml_op_scope:
    push rbx
    push r12
    push r13
    sub rsp, 16
    call aml_byte
    call aml_pkglen
    jc .bad
    mov rbx, rax                        ; end
    mov rdi, rsp
    call aml_name
    jc .bad
    mov rdi, rsp
    mov rsi, [r15 + aml_frame.scope]
    call aml_resolve
    test rax, rax
    jnz .have
    ; a scope that was never declared: make it, as firmware expects
    mov rdi, rsp
    mov esi, AML_T_SCOPE
    call aml_new_named
    test rax, rax
    jz .missing
.have:
    mov r13, [r15 + aml_frame.scope]
    mov [r15 + aml_frame.scope], rax
    mov rdi, rbx
    call aml_run_block
    mov [r15 + aml_frame.scope], r13
    jmp .out
.missing:
    call aml_err_missing
    jmp .out
.bad:
    mov eax, -AML_EBADCODE
.out:
    add rsp, 16
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Device (5B 82), Processor (5B 83), PowerResource (5B 84),
; ThermalZone (5B 85): PkgLength NameString [fixed fields] TermList
; -----------------------------------------------------------------------------
aml_op_device:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 24
    call aml_byte
    call aml_byte
    mov r12d, eax                       ; 0x82-0x85
    call aml_pkglen
    jc .bad
    mov rbx, rax
    mov rdi, rsp
    call aml_name
    jc .bad
    ; fixed fields: Processor: id, P_BLK address, length (6 bytes);
    ; PowerResource: system level, resource order (3 bytes)
    xor edi, edi
    mov r14d, AML_T_DEVICE
    cmp r12d, 0x83
    jne .pr
    mov edi, 6
    mov r14d, AML_T_PROCESSOR
.pr:
    cmp r12d, 0x84
    jne .tz
    mov edi, 3
    mov r14d, AML_T_POWERRES
.tz:
    cmp r12d, 0x85
    jne .fixed
    mov r14d, AML_T_THERMAL
.fixed:
    test edi, edi
    jz .create
    call aml_bytes
    jc .bad
    cmp r12d, 0x83                      ; keep the processor ID
    jne .create
    movzx eax, byte [rax]
    mov [rsp + 16], rax
.create:
    mov rdi, rsp
    mov esi, r14d
    call aml_new_named
    test rax, rax
    jz .missing
    cmp r12d, 0x83
    jne .run
    mov rcx, [rsp + 16]
    mov [rax + aml_node.x0], rcx
.run:
    mov r13, [r15 + aml_frame.scope]
    mov [r15 + aml_frame.scope], rax
    mov rdi, rbx
    call aml_run_block
    mov [r15 + aml_frame.scope], r13
    jmp .out
.missing:
    call aml_err_missing
    jmp .out
.bad:
    mov eax, -AML_EBADCODE
.out:
    add rsp, 24
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Method (0x14): PkgLength NameString MethodFlags TermList
; The body is kept, not run.
; -----------------------------------------------------------------------------
aml_op_method:
    push rbx
    push r12
    sub rsp, 24
    call aml_byte
    call aml_pkglen
    jc .bad
    mov rbx, rax
    mov rdi, rsp
    call aml_name
    jc .bad
    call aml_byte
    jc .bad
    mov r12d, eax
    mov rdi, rsp
    mov esi, AML_T_METHOD
    call aml_new_named
    test rax, rax
    jz .missing
    test edx, edx
    jnz .dup
    mov rcx, [r15 + aml_frame.ip]
    mov [rax + aml_node.x0], rcx
    mov [rax + aml_node.x1], rbx
    mov ecx, r12d
    and ecx, 7
    mov [rax + aml_node.x2], rcx
    test r12d, 8
    jz .done
    or dword [rax + aml_node.flags], AML_NODE_SERIAL
    jmp .done
.dup:
    inc dword [rel aml_dup_names]
.done:
    mov [r15 + aml_frame.ip], rbx
    xor eax, eax
    jmp .out
.missing:
    call aml_err_missing
    jmp .out
.bad:
    mov eax, -AML_EBADCODE
.out:
    add rsp, 24
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Alias (0x06): NameString (existing) NameString (new)
; -----------------------------------------------------------------------------
aml_op_alias:
    push rbx
    sub rsp, 32
    call aml_byte
    mov rdi, rsp
    call aml_name
    jc .bad
    lea rdi, [rsp + 16]
    call aml_name
    jc .bad
    mov rdi, rsp
    mov rsi, [r15 + aml_frame.scope]
    call aml_resolve
    test rax, rax
    jz .ok                              ; nothing to name: skipped
    mov rbx, rax
    lea rdi, [rsp + 16]
    mov esi, AML_T_ALIAS
    call aml_new_named
    test rax, rax
    jz .ok
    test edx, edx
    jnz .ok
    mov [rax + aml_node.value + aml_value.data], rbx
.ok:
    xor eax, eax
    jmp .out
.bad:
    mov eax, -AML_EBADCODE
.out:
    add rsp, 32
    pop rbx
    ret

; -----------------------------------------------------------------------------
; External (0x15): NameString ObjectType ArgumentCount
; A name another table defines. Unknown so far: a placeholder, so calls to
; it parse with the right argument count; the definition replaces it.
; -----------------------------------------------------------------------------
aml_op_external:
    push rbx
    push r12
    sub rsp, 24
    call aml_byte
    mov rdi, rsp
    call aml_name
    jc .bad
    mov edi, 2
    call aml_bytes
    jc .bad
    movzx ebx, byte [rax]               ; type
    movzx r12d, byte [rax + 1]          ; arguments
    mov rdi, rsp
    mov rsi, [r15 + aml_frame.scope]
    call aml_resolve
    test rax, rax
    jnz .ok
    mov rdi, rsp
    mov rsi, [r15 + aml_frame.scope]
    call aml_create
    test rax, rax
    jz .ok                              ; parent missing too: nothing to do
    or dword [rax + aml_node.flags], AML_NODE_EXTERNAL
    mov [rax + aml_node.value + aml_value.type], bl
    and r12d, 7
    mov [rax + aml_node.x2], r12
.ok:
    xor eax, eax
    jmp .out
.bad:
    mov eax, -AML_EBADCODE
.out:
    add rsp, 24
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Mutex (5B 01): NameString SyncFlags; Event (5B 02): NameString
; One fiber runs AML, so these only need to exist.
; -----------------------------------------------------------------------------
aml_op_sync_object:
    push rbx
    sub rsp, 16
    call aml_byte
    call aml_byte
    mov ebx, AML_T_EVENT
    cmp eax, 0x01
    jne .name
    mov ebx, AML_T_MUTEX
.name:
    mov rdi, rsp
    call aml_name
    jc .bad
    cmp ebx, AML_T_MUTEX
    jne .create
    call aml_byte                       ; sync flags
    jc .bad
.create:
    mov rdi, rsp
    mov esi, ebx
    call aml_new_named
    xor eax, eax
    jmp .out
.bad:
    mov eax, -AML_EBADCODE
.out:
    add rsp, 16
    pop rbx
    ret

; -----------------------------------------------------------------------------
; OperationRegion (5B 80): NameString RegionSpace Offset Length
; -----------------------------------------------------------------------------
aml_op_region:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 24
    call aml_byte
    call aml_byte
    mov rdi, rsp
    call aml_name
    jc .bad
    call aml_byte
    jc .bad
    mov r12d, eax                       ; space
    call aml_eval_int
    test eax, eax
    jnz .out
    mov r13, rdx                        ; offset
    call aml_eval_int
    test eax, eax
    jnz .out
    mov r14, rdx                        ; length
    mov rdi, rsp
    mov esi, AML_T_REGION
    call aml_new_named
    test rax, rax
    jz .missing
    test edx, edx
    jnz .dup
    mov [rax + aml_node.x0], r13
    mov [rax + aml_node.x1], r14
    mov [rax + aml_node.x2], r12
    xor eax, eax
    jmp .out
.dup:
    inc dword [rel aml_dup_names]
    xor eax, eax
    jmp .out
.missing:
    call aml_err_missing
    jmp .out
.bad:
    mov eax, -AML_EBADCODE
.out:
    add rsp, 24
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Field (5B 81): PkgLength Region FieldFlags FieldList
; IndexField (5B 86): PkgLength Index Data FieldFlags FieldList
; BankField (5B 87): PkgLength Region Bank BankValue FieldFlags FieldList
; Each named entry becomes a field node in the current scope.
; -----------------------------------------------------------------------------
aml_op_field:
    push rbx
    push r12
    push r13
    push r14
    push rbp
    sub rsp, 64                         ; path, path, field path, bit length
    call aml_byte
    call aml_byte
    mov ebp, eax                        ; 0x81, 0x86, 0x87
    call aml_pkglen
    jc .bad
    mov rbx, rax                        ; end of the field list
    mov rdi, rsp
    call aml_name
    jc .bad
    mov rdi, rsp
    mov rsi, [r15 + aml_frame.scope]
    call aml_resolve
    mov r12, rax                        ; region, or index field
    xor r13d, r13d                      ; second node (data or bank)
    xor r14d, r14d                      ; access byte and kind
    cmp ebp, 0x81
    je .flags
    lea rdi, [rsp + 16]
    call aml_name
    jc .bad
    lea rdi, [rsp + 16]
    mov rsi, [r15 + aml_frame.scope]
    call aml_resolve
    mov r13, rax
    mov r14d, AML_FIELD_INDEX
    cmp ebp, 0x86
    je .flags
    mov r14d, AML_FIELD_BANK
    call aml_eval_int
    test eax, eax
    jnz .out
    shl rdx, 16
    or r14, rdx
.flags:
    call aml_byte
    jc .bad
    or r14, rax                         ; access type, lock, update rule
    test r12, r12
    jz .skip_list                       ; nothing to attach the fields to
    xor ebp, ebp                        ; bit position
.entry:
    mov rax, [r15 + aml_frame.ip]
    cmp rax, rbx
    jae .done
    call aml_peek
    cmp eax, 0x00
    je .reserved
    cmp eax, 0x01
    je .access
    cmp eax, 0x02
    je .connect
    cmp eax, 0x03
    je .ext_access
    ; NameSeg PkgLength(bits)
    mov edi, 4
    call aml_bytes
    jc .bad
    mov qword [rsp + 32], 0
    mov byte [rsp + 32 + aml_path.count], 1
    mov [rsp + 32 + aml_path.segs], rax
    call aml_pkglen_value
    jc .bad
    mov [rsp + 48], rax                 ; bit length
    lea rdi, [rsp + 32]
    mov esi, AML_T_FIELD
    call aml_new_named
    mov rcx, [rsp + 48]
    test rax, rax
    jz .advance
    test edx, edx
    jnz .advance_dup
    mov [rax + aml_node.x0], r12
    mov edx, ebp
    mov r8, rcx
    shl r8, 32
    or rdx, r8
    mov [rax + aml_node.x1], rdx
    mov [rax + aml_node.x2], r14
    mov [rax + aml_node.pad], r13
    jmp .advance
.advance_dup:
    inc dword [rel aml_dup_names]
.advance:
    add ebp, ecx
    jmp .entry
.reserved:
    call aml_byte
    call aml_pkglen_value
    jc .bad
    add ebp, eax
    jmp .entry
.access:
    call aml_byte
    call aml_byte                       ; access type
    jc .bad
    and r14, ~0x0F
    and eax, 0x0F
    or r14, rax
    call aml_byte                       ; access attribute
    jc .bad
    jmp .entry
.ext_access:
    call aml_byte
    call aml_byte
    jc .bad
    and r14, ~0x0F
    and eax, 0x0F
    or r14, rax
    mov edi, 2                          ; attribute, length
    call aml_bytes
    jc .bad
    jmp .entry
.connect:
    ; the connection (GPIO pins, serial bus) is read but not used yet
    call aml_byte
    call aml_peek
    cmp eax, 0x11
    je .connect_buffer
    lea rdi, [rsp + 16]
    call aml_name
    jc .bad
    jmp .entry
.connect_buffer:
    lea rdi, [rsp + 16]
    call aml_eval
    test eax, eax
    jnz .out
    jmp .entry
.skip_list:
    mov [r15 + aml_frame.ip], rbx
.done:
    mov [r15 + aml_frame.ip], rbx
    xor eax, eax
    jmp .out
.bad:
    mov eax, -AML_EBADCODE
.out:
    add rsp, 64
    pop rbp
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_slot — the storage a buffer or package operand lives in, so buffer
;            fields and Index reach the object itself, not a copy.
;            LocalX, ArgX and names give their own slot; anything else is
;            evaluated into a temporary slot.
; Output: EAX = 0 or error; RDX = aml_value*
; -----------------------------------------------------------------------------
aml_slot:
    push rbx
    sub rsp, 16
    call aml_peek
    cmp eax, 0x60
    jb .name
    cmp eax, 0x6E
    ja .name
    call aml_byte
    cmp eax, 0x68
    jae .arg
    sub eax, 0x60
    shl eax, 4
    lea rdx, [r15 + aml_frame.locals + rax]
    jmp .ok
.arg:
    sub eax, 0x68
    shl eax, 4
    lea rdx, [r15 + aml_frame.args + rax]
    ; an argument holding a reference stands for what it refers to
    cmp byte [rdx + aml_value.type], AML_T_REF
    jne .ok
    cmp byte [rdx + aml_value.sub], AML_REF_SLOT
    jne .ref_node
    mov rdx, [rdx + aml_value.data]
    jmp .ok
.ref_node:
    cmp byte [rdx + aml_value.sub], AML_REF_NODE
    jne .ok
    mov rdx, [rdx + aml_value.data]
    lea rdx, [rdx + aml_node.value]
    jmp .ok
.name:
    call aml_is_lead
    jne .eval
    mov rdi, rsp
    call aml_name
    jc .bad
    mov rdi, rsp
    mov rsi, [r15 + aml_frame.scope]
    call aml_resolve
    test rax, rax
    jz .missing
    movzx ecx, byte [rax + aml_node.value + aml_value.type]
    cmp ecx, AML_T_BUFFER
    je .node
    cmp ecx, AML_T_PACKAGE
    je .node
    cmp ecx, AML_T_STRING
    je .node
    ; a method, field or other object: its value, in a temporary slot
    mov rbx, rax
    mov edi, aml_value_size
    call aml_talloc
    test rax, rax
    jz .oom
    mov rdi, rbx
    mov rsi, rax
    mov rbx, rax
    call aml_read_node_value
    mov rdx, rbx
    jmp .out
.node:
    lea rdx, [rax + aml_node.value]
    jmp .ok
.eval:
    mov edi, aml_value_size
    call aml_talloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov rdi, rax
    call aml_eval
    mov rdx, rbx
    jmp .out
.ok:
    xor eax, eax
    jmp .out
.missing:
    call aml_err_missing
    jmp .out
.oom:
    mov eax, -AML_ENOMEM
    jmp .out
.bad:
    mov eax, -AML_EBADCODE
.out:
    add rsp, 16
    pop rbx
    ret

; -----------------------------------------------------------------------------
; CreateBitField (8D), CreateByteField (8C), CreateWordField (8B),
; CreateDWordField (8A), CreateQWordField (8F): SourceBuff Index NameString
; CreateField (5B 13): SourceBuff BitIndex NumBits NameString
; -----------------------------------------------------------------------------
aml_op_create_field:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 24
    call aml_byte
    mov r12d, eax
    cmp eax, 0x5B
    jne .source
    call aml_byte
    mov r12d, 0x13
.source:
    call aml_slot
    test eax, eax
    jnz .out
    mov rbx, rdx                        ; the buffer's slot
    cmp byte [rbx + aml_value.type], AML_T_BUFFER
    jne .type
    call aml_eval_int
    test eax, eax
    jnz .out
    mov r13, rdx                        ; index
    ; bit offset and size by opcode
    cmp r12d, 0x13
    je .create_field
    mov r14d, 1
    cmp r12d, 0x8D
    je .sized                           ; bit index, 1 bit
    shl r13, 3                          ; byte index in bits
    mov r14d, 8
    cmp r12d, 0x8C
    je .sized
    mov r14d, 16
    cmp r12d, 0x8B
    je .sized
    mov r14d, 32
    cmp r12d, 0x8A
    je .sized
    mov r14d, 64
    jmp .sized
.create_field:
    call aml_eval_int
    test eax, eax
    jnz .out
    mov r14, rdx
.sized:
    mov rdi, rsp
    call aml_name
    jc .bad
    ; the field must fit in the buffer now (it may grow later, never shrink
    ; below what reads check again)
    mov eax, [rbx + aml_value.len]
    shl rax, 3
    lea rcx, [r13 + r14]
    cmp rcx, rax
    ja .index
    mov rdi, rsp
    mov esi, AML_T_BUFFIELD
    call aml_new_named
    test rax, rax
    jz .missing
    test edx, edx
    jnz .dup
    mov [rax + aml_node.x0], rbx
    mov rcx, r14
    shl rcx, 32
    mov edx, r13d
    or rcx, rdx
    mov [rax + aml_node.x1], rcx
    xor eax, eax
    jmp .out
.dup:
    inc dword [rel aml_dup_names]
    xor eax, eax
    jmp .out
.index:
    mov eax, -AML_EINDEX
    jmp .out
.type:
    mov eax, -AML_ETYPE
    jmp .out
.missing:
    call aml_err_missing
    jmp .out
.bad:
    mov eax, -AML_EBADCODE
.out:
    add rsp, 24
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; If (A0): PkgLength Predicate TermList, optionally followed by
; Else (A1): PkgLength TermList
; -----------------------------------------------------------------------------
aml_op_if:
    push rbx
    push r12
    sub rsp, 8
    call aml_byte
    call aml_pkglen
    jc .bad
    mov rbx, rax
    mov r12, [r15 + aml_frame.end]      ; the predicate stays inside the If
    mov [r15 + aml_frame.end], rbx
    call aml_eval_int
    mov [r15 + aml_frame.end], r12
    test eax, eax
    jnz .out
    test rdx, rdx
    jz .false
    mov rdi, rbx
    call aml_run_block
    test eax, eax
    jnz .out
    cmp dword [r15 + aml_frame.flags], 0
    jne .out
    call aml_peek
    cmp eax, 0xA1
    jne .ok
    call aml_byte                       ; skip the Else
    call aml_pkglen
    jc .bad
    mov [r15 + aml_frame.ip], rax
    jmp .ok
.false:
    mov [r15 + aml_frame.ip], rbx
    call aml_peek
    cmp eax, 0xA1
    jne .ok
    call aml_byte
    call aml_pkglen
    jc .bad
    mov rdi, rax
    call aml_run_block
    jmp .out
.ok:
    xor eax, eax
    jmp .out
.bad:
    mov eax, -AML_EBADCODE
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; Else with no If before it: skipped
aml_op_else:
    sub rsp, 8
    call aml_byte
    call aml_pkglen
    jc .bad
    mov [r15 + aml_frame.ip], rax
    xor eax, eax
    add rsp, 8
    ret
.bad:
    mov eax, -AML_EBADCODE
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; While (A2): PkgLength Predicate TermList
; -----------------------------------------------------------------------------
aml_op_while:
    push rbx
    push r12
    push r13
    call aml_byte
    call aml_pkglen
    jc .bad
    mov rbx, rax                        ; end
    mov r12, [r15 + aml_frame.ip]       ; predicate
    mov r13, [r15 + aml_frame.end]
.loop:
    mov [r15 + aml_frame.ip], r12
    mov [r15 + aml_frame.end], rbx
    call aml_eval_int
    mov [r15 + aml_frame.end], r13
    test eax, eax
    jnz .out
    test rdx, rdx
    jz .done
    inc dword [rel aml_loops]
    cmp dword [rel aml_loops], AML_MAX_LOOPS
    ja .budget
    mov rdi, rbx
    call aml_run_block
    test eax, eax
    jnz .out
    mov eax, [r15 + aml_frame.flags]
    test eax, AML_F_RETURN
    jnz .ok
    test eax, AML_F_BREAK
    jnz .broke
    and dword [r15 + aml_frame.flags], ~AML_F_CONTINUE
    jmp .loop
.broke:
    and dword [r15 + aml_frame.flags], ~AML_F_BREAK
.done:
    mov [r15 + aml_frame.ip], rbx
.ok:
    xor eax, eax
    jmp .out
.budget:
    mov eax, -AML_EBUDGET
    jmp .out
.bad:
    mov eax, -AML_EBADCODE
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Return (A4): ArgObject
; -----------------------------------------------------------------------------
aml_op_return:
    sub rsp, 8
    call aml_byte
    lea rdi, [r15 + aml_frame.ret]
    call aml_eval
    test eax, eax
    jnz .out
    or dword [r15 + aml_frame.flags], AML_F_RETURN
.out:
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; Notify (86): NotifyObject NotifyValue
; -----------------------------------------------------------------------------
aml_op_notify:
    push rbx
    sub rsp, 16
    call aml_byte
    mov rdi, rsp
    call aml_target
    test eax, eax
    jnz .out
    call aml_eval_int
    test eax, eax
    jnz .out
    mov rax, [rel aml_notify_fn]
    test rax, rax
    jz .ok
    cmp byte [rsp + aml_value.sub], AML_REF_NODE
    jne .ok
    mov rdi, [rsp + aml_value.data]
    mov rsi, rdx
    call rax
.ok:
    xor eax, eax
.out:
    add rsp, 16
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Sleep (5B 22) milliseconds, Stall (5B 21) microseconds
; -----------------------------------------------------------------------------
aml_op_sleep:
    push rbx
    call aml_byte
    call aml_byte
    mov ebx, 1000000                    ; Sleep: ms
    cmp eax, 0x22
    je .time
    mov ebx, 1000                       ; Stall: us
.time:
    call aml_eval_int
    test eax, eax
    jnz .out
    mov rax, [rel aml_sleep_fn]
    test rax, rax
    jz .ok
    mov rdi, rdx
    imul rdi, rbx
    call rax
.ok:
    xor eax, eax
.out:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Release (5B 27), Signal (5B 24), Reset (5B 26): SuperName
; One fiber runs AML, so there is nothing to wake or release.
; -----------------------------------------------------------------------------
aml_op_release:
    sub rsp, 24
    call aml_byte
    call aml_byte
    mov rdi, rsp
    call aml_target
    add rsp, 24
    ret

; -----------------------------------------------------------------------------
; aml_read_node_value — a named object's current value
; Methods are not called here (aml_eval_name does that).
; Input:  RDI = node, RSI = destination value*
; -----------------------------------------------------------------------------
aml_read_node_value:
    movzx eax, byte [rdi + aml_node.value + aml_value.type]
    cmp eax, AML_T_FIELD
    je aml_field_read
    cmp eax, AML_T_BUFFIELD
    je aml_buffield_read
    cmp eax, AML_T_PACKAGE
    jbe .data
    ; an object (device, mutex, region...): its type and itself
    mov qword [rsi], 0
    mov [rsi + aml_value.type], al
    mov [rsi + aml_value.data], rdi
    xor eax, eax
    ret
.data:
    lea rax, [rdi + aml_node.value]
    mov rdi, rsi
    mov rsi, rax
    jmp aml_copy

; -----------------------------------------------------------------------------
; aml_eval_name — a NameString as an operand: call a method (reading its
;                 arguments from the bytecode), or read an object
; Input:  RDI = destination value*
; -----------------------------------------------------------------------------
aml_eval_name:
    push rbx
    push r12
    push r13
    sub rsp, 16
    mov rbx, rdi
    mov rdi, rsp
    call aml_name
    jc .bad
    mov rdi, rsp
    mov rsi, [r15 + aml_frame.scope]
    call aml_resolve
    test rax, rax
    jz .missing
    mov r12, rax
    cmp byte [r12 + aml_node.value + aml_value.type], AML_T_METHOD
    je .call
    mov rdi, r12
    mov rsi, rbx
    call aml_read_node_value
    jmp .out
.call:
    ; the arguments follow in the bytecode
    mov edi, AML_ARGS * aml_value_size
    call aml_talloc
    test rax, rax
    jz .oom
    mov r13, rax
    movzx ecx, byte [r12 + aml_node.x2]
    and ecx, 7
    xor edx, edx
.arg:
    cmp edx, ecx
    jae .args_done
    push rcx
    push rdx
    shl edx, 4
    lea rdi, [r13 + rdx]
    call aml_eval
    pop rdx
    pop rcx
    test eax, eax
    jnz .out
    inc edx
    jmp .arg
.args_done:
    mov rdi, r12
    mov rsi, r13
    mov rdx, rbx
    call aml_call
    jmp .out
.missing:
    call aml_err_missing
    jmp .out
.oom:
    mov eax, -AML_ENOMEM
    jmp .out
.bad:
    mov eax, -AML_EBADCODE
.out:
    add rsp, 16
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_call — run a method
; Input:  RDI = method node, RSI = its arguments (aml_value[7]),
;         RDX = destination value* for the result
; A method that returns nothing gives Integer 0.
; -----------------------------------------------------------------------------
global aml_call
aml_call:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp rsp, [rel aml_stack_limit]
    jb .budget
    test dword [rbx + aml_node.flags], AML_NODE_NATIVE
    jnz .native
    test dword [rbx + aml_node.flags], AML_NODE_EXTERNAL
    jnz .missing                        ; declared, never defined
    mov eax, [r15 + aml_frame.depth]
    inc eax
    cmp eax, AML_MAX_DEPTH
    ja .budget
    mov r14d, eax
    mov edi, aml_frame_size
    call aml_talloc
    test rax, rax
    jz .oom
    mov rcx, [rbx + aml_node.x0]
    mov [rax + aml_frame.ip], rcx
    mov rcx, [rbx + aml_node.x1]
    mov [rax + aml_frame.end], rcx
    mov [rax + aml_frame.scope], rbx
    mov [rax + aml_frame.method], rbx
    mov [rax + aml_frame.parent], r15
    mov [rax + aml_frame.depth], r14d
    ; arguments: 7 values
    lea rdi, [rax + aml_frame.args]
    mov rsi, r12
    mov ecx, AML_ARGS * aml_value_size
    rep movsb
    mov r14, r15
    mov r15, rax
    call aml_run_list
    mov r12d, eax                       ; status
    test eax, eax
    jnz .unlink_start
    ; the result; a method that returns nothing gives Integer 0
    mov rax, [r15 + aml_frame.ret]
    mov rcx, [r15 + aml_frame.ret + 8]
    mov [r13], rax
    mov [r13 + 8], rcx
    cmp byte [r13 + aml_value.type], AML_T_UNINIT
    jne .unlink_start
    mov rdi, r13
    xor esi, esi
    call aml_set_int
.unlink_start:
    ; the method's own names go away with it
    mov rcx, [r15 + aml_frame.created]
.unlink:
    test rcx, rcx
    jz .unlinked
    mov rdi, [rcx + aml_node.parent]
    lea rdx, [rdi + aml_node.child]
.find:
    mov rax, [rdx]
    test rax, rax
    jz .next_created
    cmp rax, rcx
    je .remove
    lea rdx, [rax + aml_node.next]
    jmp .find
.remove:
    mov rax, [rcx + aml_node.next]
    mov [rdx], rax
.next_created:
    mov rcx, [rcx + aml_node.pad]
    jmp .unlink
.unlinked:
    mov r15, r14
    mov eax, r12d
    jmp .out
.native:
    mov rdi, r12
    mov rsi, r13
    call [rbx + aml_node.x0]
    jmp .out
.budget:
    mov eax, -AML_EBUDGET
    jmp .out
.missing:
    call aml_err_missing
    jmp .out
.oom:
    mov eax, -AML_ENOMEM
.out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_target — read a SuperName or Target into a reference
; Input:  RDI = aml_value* to receive an AML_T_REF
; -----------------------------------------------------------------------------
aml_target:
    push rbx
    sub rsp, 16
    mov rbx, rdi
    mov qword [rbx], 0
    mov qword [rbx + 8], 0
    mov byte [rbx + aml_value.type], AML_T_REF
    call aml_peek
    cmp eax, 0x00
    je .none
    cmp eax, 0x60
    jb .other
    cmp eax, 0x6E
    ja .other
    call aml_byte
    cmp eax, 0x68
    jae .arg
    sub eax, 0x60
    shl eax, 4
    lea rdx, [r15 + aml_frame.locals + rax]
    jmp .slot
.arg:
    sub eax, 0x68
    shl eax, 4
    lea rdx, [r15 + aml_frame.args + rax]
    cmp byte [rdx + aml_value.type], AML_T_REF
    jne .slot
    mov rax, [rdx]                      ; store through the reference
    mov rcx, [rdx + 8]
    mov [rbx], rax
    mov [rbx + 8], rcx
    jmp .ok
.slot:
    mov byte [rbx + aml_value.sub], AML_REF_SLOT
    mov [rbx + aml_value.data], rdx
    jmp .ok
.none:
    call aml_byte
    mov byte [rbx + aml_value.sub], AML_REF_NONE
    jmp .ok
.other:
    cmp eax, 0x5B
    jne .not_debug
    mov rcx, [r15 + aml_frame.ip]
    lea rdx, [rcx + 1]
    cmp rdx, [r15 + aml_frame.end]
    jae .bad
    cmp byte [rcx + 1], 0x31
    jne .expr
    mov edi, 2
    call aml_bytes
    mov byte [rbx + aml_value.sub], AML_REF_DEBUG
    jmp .ok
.not_debug:
    cmp eax, 0x83                       ; DerefOf: what its operand refers to
    je .deref
    call aml_is_lead
    jne .expr
    mov rdi, rsp
    call aml_name
    jc .bad
    mov rdi, rsp
    mov rsi, [r15 + aml_frame.scope]
    call aml_resolve
    test rax, rax
    jz .missing
    mov byte [rbx + aml_value.sub], AML_REF_NODE
    mov [rbx + aml_value.data], rax
    jmp .ok
.deref:
    call aml_byte
.expr:
    ; Index(...) and similar: an expression giving a reference
    mov rdi, rbx
    call aml_eval
    test eax, eax
    jnz .out
    cmp byte [rbx + aml_value.type], AML_T_REF
    jne .type
.ok:
    xor eax, eax
    jmp .out
.type:
    mov eax, -AML_ETYPE
    jmp .out
.missing:
    call aml_err_missing
    jmp .out
.bad:
    mov eax, -AML_EBADCODE
.out:
    add rsp, 16
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_ref_read — the value a reference refers to
; Input:  RDI = reference value*, RSI = destination value*
; -----------------------------------------------------------------------------
aml_ref_read:
    movzx eax, byte [rdi + aml_value.sub]
    mov rcx, [rdi + aml_value.data]
    cmp eax, AML_REF_SLOT
    je .slot
    cmp eax, AML_REF_NODE
    je .node
    cmp eax, AML_REF_BYTE
    je .byte
    mov eax, -AML_ETYPE
    ret
.slot:
    mov rdi, rsi
    mov rsi, rcx
    jmp aml_copy
.node:
    cmp byte [rcx + aml_node.value + aml_value.type], AML_T_METHOD
    je .method
    mov rdi, rcx
    jmp aml_read_node_value
.method:
    mov eax, -AML_ETYPE
    ret
.byte:
    movzx eax, byte [rcx]
    mov rdi, rsi
    mov rsi, rax
    call aml_set_int
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; aml_store — Store: put a value where a reference points, converting it to
;             the type of a named data object it lands in
; Input:  RDI = reference value*, RSI = value*
; -----------------------------------------------------------------------------
aml_store:
    push rbx
    push r12
    push r13
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    movzx eax, byte [rbx + aml_value.sub]
    mov r13, [rbx + aml_value.data]
    cmp eax, AML_REF_NONE
    je .ok
    cmp eax, AML_REF_DEBUG
    je .debug
    cmp eax, AML_REF_SLOT
    je .slot
    cmp eax, AML_REF_BYTE
    je .byte
    cmp eax, AML_REF_NODE
    jne .type
    movzx eax, byte [r13 + aml_node.value + aml_value.type]
    cmp eax, AML_T_FIELD
    je .field
    cmp eax, AML_T_BUFFIELD
    je .buffield
    cmp eax, AML_T_INTEGER
    je .to_int
    cmp eax, AML_T_BUFFER
    je .to_buffer
    cmp eax, AML_T_STRING
    je .replace
    cmp eax, AML_T_PACKAGE
    je .replace
    cmp eax, AML_T_UNINIT
    je .replace
    jmp .type
.replace:
    lea rdi, [r13 + aml_node.value]
    mov rsi, r12
    call aml_copy
    jmp .out
.slot:
    mov rdi, r13
    mov rsi, r12
    call aml_copy
    jmp .out
.to_int:
    mov rdi, r12
    xor esi, esi
    call aml_to_int
    test eax, eax
    jnz .out
    lea rdi, [r13 + aml_node.value]
    mov rsi, rdx
    call aml_set_int
    xor eax, eax
    jmp .out
.to_buffer:
    ; the buffer keeps its length: the source is cut or padded with zeros
    mov rdi, rsp
    mov rsi, r12
    call aml_to_buffer
    test eax, eax
    jnz .out
    mov rdi, [r13 + aml_node.value + aml_value.data]
    mov ecx, [r13 + aml_node.value + aml_value.len]
    mov rsi, [rsp + aml_value.data]
    mov edx, [rsp + aml_value.len]
    xor r8d, r8d
.copy:
    cmp r8d, ecx
    jae .ok
    xor eax, eax
    cmp r8d, edx
    jae .put
    mov al, [rsi + r8]
.put:
    mov [rdi + r8], al
    inc r8d
    jmp .copy
.field:
    mov rdi, r13
    mov rsi, r12
    call aml_field_write
    jmp .out
.buffield:
    mov rdi, r13
    mov rsi, r12
    call aml_buffield_write
    jmp .out
.byte:
    mov rdi, r12
    xor esi, esi
    call aml_to_int
    test eax, eax
    jnz .out
    mov [r13], dl
    jmp .ok
.debug:
    mov rax, [rel aml_debug_fn]
    test rax, rax
    jz .ok
    mov rdi, r12
    call rax
.ok:
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

%endif ; LIB_IO_ACPI_AML_EXEC_ASM
