; =============================================================================
; Utkarsha OS — lib/io/acpi/aml/api.asm
; =============================================================================
; What the rest of the OS calls:
;   aml_init        memory and the predefined names
;   aml_load        run a DSDT or SSDT: builds the namespace
;   aml_find        a node by path ("\_SB.PCI0._STA")
;   aml_eval_path   evaluate a path: call a method with arguments, or read
;                   an object
; One caller at a time (ROADMAP.md decision 4: one fiber runs AML).
;
; Values returned by aml_eval_path live in temporary memory until the next
; aml_load or aml_eval_path; copy what must be kept.
; =============================================================================

%ifndef LIB_IO_ACPI_AML_API_ASM
%define LIB_IO_ACPI_AML_API_ASM

%define AML_TABLE_HEADER    36
%define AML_MAX_PATH_SEGS   16

section .bss
alignb 8
aml_path_segs:      resd AML_MAX_PATH_SEGS
global aml_fail_offset
aml_fail_offset:    resq 1          ; where the last load stopped, from the
                                    ; table start (diagnostics)

section .rodata
; Feature strings _OSI answers "supported" for. Strings naming another
; operating system are answered later by a table an admin can change
; (ROADMAP.md decision 6); until then they are "not supported".
aml_osi_strings:
    db "Module Device", 0
    db "Processor Device", 0
    db "3.0 Thermal Model", 0
    db "3.0 _SCP Extensions", 0
    db "Processor Aggregator Device", 0
    db "Extended Address Space Descriptor", 0
    db 0

section .text

; -----------------------------------------------------------------------------
; aml_init — set up the interpreter
; Input:  RDI = memory for the interpreter (16-byte aligned), RSI = its size
; Output: EAX = 0 or -AML_ENOMEM
; -----------------------------------------------------------------------------
global aml_init
aml_init:
    sub rsp, 8
    call aml_heap_init
    mov qword [rel aml_int_ones], -1
    mov dword [rel aml_int_bytes], 8
    mov dword [rel aml_dup_names], 0
    mov qword [rel aml_node_frame], 0
    mov dword [rel aml_oom], 0
    call aml_ns_init
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; aml_top_frame — a frame for running at the root (temporary memory)
; Output: RAX = frame or 0
; -----------------------------------------------------------------------------
aml_top_frame:
    sub rsp, 8
    mov edi, aml_frame_size
    call aml_talloc
    test rax, rax
    jz .out
    mov rcx, [rel aml_root]
    mov [rax + aml_frame.scope], rcx
.out:
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; aml_begin — start of every entry point: fresh temporary memory, limits
; Input:  RAX = the caller's RSP at entry
; -----------------------------------------------------------------------------
%macro AML_BEGIN 0
    call aml_temp_reset
    mov dword [rel aml_loops], 0
    mov dword [rel aml_oom], 0
    lea rax, [rsp - AML_STACK_BUDGET]
    mov [rel aml_stack_limit], rax
%endmacro

; -----------------------------------------------------------------------------
; aml_load — load a definition block (DSDT or SSDT)
; Input:  RDI = the table (header included)
; Output: EAX = 0, or the first error; aml_fail_offset says where
; The first table's revision sets the integer width: below 2, 32 bits.
; -----------------------------------------------------------------------------
global aml_load
aml_load:
    push rbx
    push r15
    sub rsp, 8
    mov rbx, rdi
    AML_BEGIN
    mov eax, [rbx + 4]                  ; length
    cmp eax, AML_TABLE_HEADER
    jb .bad
    cmp byte [rbx + 8], 2               ; revision
    jae .width_set
    mov eax, 0xFFFFFFFF
    mov [rel aml_int_ones], rax
    mov dword [rel aml_int_bytes], 4
.width_set:
    call aml_top_frame
    test rax, rax
    jz .oom
    mov r15, rax
    lea rcx, [rbx + AML_TABLE_HEADER]
    mov [r15 + aml_frame.ip], rcx
    mov ecx, [rbx + 4]
    add rcx, rbx
    mov [r15 + aml_frame.end], rcx
    call aml_run_list
    mov rcx, [r15 + aml_frame.ip]
    sub rcx, rbx
    mov [rel aml_fail_offset], rcx
    jmp .out
.bad:
    mov eax, -AML_EBADCODE
    jmp .out
.oom:
    mov eax, -AML_ENOMEM
.out:
    add rsp, 8
    pop r15
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_path_from_text — turn "\_SB.PCI0._STA" into an aml_path
; Short segments are padded with '_'. Relative text starts at the root.
; Input:  RDI = text, RSI = aml_path* to fill
; Output: CF = 1 when the text is not a path
; -----------------------------------------------------------------------------
aml_path_from_text:
    mov qword [rsi], 0
    mov qword [rsi + 8], 0
    mov byte [rsi + aml_path.root], 1
    lea r8, [rel aml_path_segs]
    mov [rsi + aml_path.segs], r8
    cmp byte [rdi], '\'
    jne .segs
    inc rdi
.segs:
    cmp byte [rdi], 0
    je .ok
    movzx ecx, byte [rsi + aml_path.count]
    cmp ecx, AML_MAX_PATH_SEGS
    jae .bad
    mov eax, '____'
    xor edx, edx                        ; characters in this segment
.char:
    movzx r9d, byte [rdi]
    test r9d, r9d
    jz .seg_done
    cmp r9d, '.'
    je .seg_dot
    cmp edx, 4
    jae .bad
    lea ecx, [rdx * 8]
    mov r10d, 0xFF
    shl r10d, cl
    not r10d
    and eax, r10d
    shl r9d, cl
    or eax, r9d
    inc edx
    inc rdi
    jmp .char
.seg_dot:
    inc rdi
.seg_done:
    test edx, edx
    jz .bad
    movzx ecx, byte [rsi + aml_path.count]
    mov [r8 + rcx * 4], eax
    inc byte [rsi + aml_path.count]
    jmp .segs
.ok:
    clc
    ret
.bad:
    stc
    ret

; -----------------------------------------------------------------------------
; aml_find — the node a path names
; Input:  RDI = text path
; Output: RAX = node, or 0
; -----------------------------------------------------------------------------
global aml_find
aml_find:
    sub rsp, 24
    mov rsi, rsp
    call aml_path_from_text
    jc .none
    mov rdi, rsp
    mov rsi, [rel aml_root]
    call aml_resolve
    jmp .out
.none:
    xor eax, eax
.out:
    add rsp, 24
    ret

; -----------------------------------------------------------------------------
; aml_eval_path — evaluate a named object
; Input:  RDI = text path, RSI = arguments (aml_value[], or 0),
;         EDX = how many, RCX = destination value*
; Output: EAX = 0 or a negative AML_E* error
; A method gets its arguments; any other object is read (fields from their
; region). Giving a method fewer arguments than it takes is -AML_EARGS.
; -----------------------------------------------------------------------------
global aml_eval_path
aml_eval_path:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    mov rbx, rdi
    AML_BEGIN
    mov rdi, rbx
    call aml_find
    test rax, rax
    jz .missing
    mov rbx, rax
    call aml_top_frame
    test rax, rax
    jz .oom
    mov r15, rax
    cmp byte [rbx + aml_node.value + aml_value.type], AML_T_METHOD
    je .method
    mov rdi, rbx
    mov rsi, r14
    call aml_read_node_value
    jmp .out
.method:
    movzx eax, byte [rbx + aml_node.x2]
    and eax, 7
    cmp r13d, eax
    jb .args
    cmp r13d, AML_ARGS
    ja .args
    ; the arguments, copied into a full set of seven
    mov edi, AML_ARGS * aml_value_size
    call aml_talloc
    test rax, rax
    jz .oom
    mov rdi, rax
    mov rsi, r12
    mov ecx, r13d
    shl ecx, 4
    test r12, r12
    jz .call
    push rax
    rep movsb
    pop rax
.call:
    mov rdi, rbx
    mov rsi, rax
    mov rdx, r14
    call aml_call
    jmp .out
.args:
    mov eax, -AML_EARGS
    jmp .out
.missing:
    mov eax, -AML_ENOTFOUND
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
; aml_native_osi — \_OSI (feature string): Ones when supported, else 0
; Input:  RDI = arguments, RSI = destination value*
; -----------------------------------------------------------------------------
aml_native_osi:
    push rbx
    mov rbx, rsi
    cmp byte [rdi + aml_value.type], AML_T_STRING
    jne .type
    mov r8, [rdi + aml_value.data]
    mov r9d, [rdi + aml_value.len]
    lea rsi, [rel aml_osi_strings]
.next:
    cmp byte [rsi], 0
    je .no
    ; compare the argument (length R9D) with the NUL-terminated entry
    xor ecx, ecx
.cmp:
    movzx eax, byte [rsi + rcx]
    cmp ecx, r9d
    je .end_arg
    cmp al, [r8 + rcx]
    jne .skip
    inc ecx
    jmp .cmp
.end_arg:
    test eax, eax
    jz .yes
.skip:
    ; to the next entry
.skip_char:
    cmp byte [rsi], 0
    je .skipped
    inc rsi
    jmp .skip_char
.skipped:
    inc rsi
    jmp .next
.yes:
    mov rdi, rbx
    mov rsi, -1
    call aml_set_int
    xor eax, eax
    pop rbx
    ret
.no:
    mov rdi, rbx
    xor esi, esi
    call aml_set_int
    xor eax, eax
    pop rbx
    ret
.type:
    mov eax, -AML_ETYPE
    pop rbx
    ret

%endif ; LIB_IO_ACPI_AML_API_ASM
