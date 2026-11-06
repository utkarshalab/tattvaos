; =============================================================================
; Utkarsha OS — lib/io/acpi/aml/ns.asm
; =============================================================================
; The namespace: a tree of nodes named by four-character segments, and the
; lookup rules from the specification:
;   \A.B      absolute
;   ^A        relative, one level up per ^
;   A.B       relative to the current scope, no search
;   A         a single segment with no prefix searches the current scope,
;             then each parent up to the root (references only, never
;             creation)
; =============================================================================

%ifndef LIB_IO_ACPI_AML_NS_ASM
%define LIB_IO_ACPI_AML_NS_ASM

; A parsed name string (aml_parse_name fills one)
struc aml_path
    .root:      resb 1          ; 1 when it starts with the root prefix
    .carets:    resb 1          ; number of ^
    .count:     resb 1          ; segments
    .pad:       resb 5
    .segs:      resq 1          ; the segments, 4 bytes each, in the AML
endstruc

%define AML_SEG(a,b,c,d)    (a | (b << 8) | (c << 16) | (d << 24))

section .bss
alignb 8
global aml_root
aml_root:           resq 1
aml_node_frame:     resq 1          ; set while a method creates names

section .rodata
aml_os_name:        db "Utkarsha OS", 0
AML_OS_NAME_LEN     equ $ - aml_os_name - 1

section .text

; -----------------------------------------------------------------------------
; aml_node_new — a new node, appended to a parent's children
; Input:  RDI = parent (0 for the root), ESI = name
; Output: RAX = node, or 0 when memory is full
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
aml_node_new:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    ; a running method's names are temporary and listed in its frame, so
    ; they can be removed when it returns
    mov rcx, [rel aml_node_frame]
    test rcx, rcx
    jnz .temp
    mov edi, aml_node_size
    call aml_alloc
    test rax, rax
    jz .out
    jmp .named
.temp:
    mov edi, aml_node_size
    call aml_talloc
    test rax, rax
    jz .out
    mov rcx, [rel aml_node_frame]
    or dword [rax + aml_node.flags], AML_NODE_TEMP
    mov rdx, [rcx + aml_frame.created]
    mov [rax + aml_node.pad], rdx
    mov [rcx + aml_frame.created], rax
.named:
    mov [rax + aml_node.name], r12d
    mov [rax + aml_node.parent], rbx
    test rbx, rbx
    jz .out
    ; append after the last child
    lea rcx, [rbx + aml_node.child]
.walk:
    mov rdx, [rcx]
    test rdx, rdx
    jz .link
    lea rcx, [rdx + aml_node.next]
    jmp .walk
.link:
    mov [rcx], rax
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_child — a node's child by name
; Input:  RDI = parent, ESI = name
; Output: RAX = the child, or 0
; Clobbers: RAX
; -----------------------------------------------------------------------------
aml_child:
    mov rax, [rdi + aml_node.child]
.next:
    test rax, rax
    jz .out
    cmp [rax + aml_node.name], esi
    je .out
    mov rax, [rax + aml_node.next]
    jmp .next
.out:
    ret

; -----------------------------------------------------------------------------
; aml_path_start — where a path begins: the root, or the scope moved up by
;                  its carets
; Input:  RDI = aml_path*, RSI = scope
; Output: RAX = node, or 0 when the carets go above the root
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
aml_path_start:
    cmp byte [rdi + aml_path.root], 0
    je .relative
    mov rax, [rel aml_root]
    ret
.relative:
    mov rax, rsi
    movzx ecx, byte [rdi + aml_path.carets]
.up:
    test ecx, ecx
    jz .out
    mov rax, [rax + aml_node.parent]
    test rax, rax
    jz .out
    dec ecx
    jmp .up
.out:
    ret

; -----------------------------------------------------------------------------
; aml_resolve — find the node a path names
; Input:  RDI = aml_path*, RSI = scope
; Output: RAX = node, or 0 when it does not exist. Aliases are followed.
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
aml_resolve:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    call aml_path_start
    test rax, rax
    jz .out
    mov r12, rax
    movzx ecx, byte [rbx + aml_path.count]
    test ecx, ecx
    jz .found                           ; "\" or "^" alone
    mov r13, [rbx + aml_path.segs]

    ; one segment, no prefix: search upward
    cmp ecx, 1
    jne .walk
    cmp byte [rbx + aml_path.root], 0
    jne .walk
    cmp byte [rbx + aml_path.carets], 0
    jne .walk
    mov esi, [r13]
.search:
    mov rdi, r12
    call aml_child
    test rax, rax
    jnz .alias
    mov r12, [r12 + aml_node.parent]
    test r12, r12
    jnz .search
    xor eax, eax
    jmp .out

.walk:
    movzx ebx, byte [rbx + aml_path.count]
.seg:
    mov rdi, r12
    mov esi, [r13]
    call aml_child
    test rax, rax
    jz .out
    mov r12, rax
    ; an alias in the middle of a path stands for its target
    cmp byte [r12 + aml_node.value + aml_value.type], AML_T_ALIAS
    jne .step
    mov r12, [r12 + aml_node.value + aml_value.data]
.step:
    add r13, 4
    dec ebx
    jnz .seg
.found:
    mov rax, r12
.alias:
    cmp byte [rax + aml_node.value + aml_value.type], AML_T_ALIAS
    jne .out
    mov rax, [rax + aml_node.value + aml_value.data]
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_create — find or make the node a path names (never searches upward)
; Input:  RDI = aml_path*, RSI = scope
; Output: RAX = node, or 0 (a parent does not exist, or memory is full);
;         EDX = 1 when the node existed already
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
aml_create:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, rdi
    call aml_path_start
    test rax, rax
    jz .fail
    mov r12, rax
    movzx r14d, byte [rbx + aml_path.count]
    test r14d, r14d
    jz .existing                        ; the root or a caret path itself
    mov r13, [rbx + aml_path.segs]
.seg:
    mov rdi, r12
    mov esi, [r13]
    call aml_child
    test rax, rax
    jz .missing
    cmp byte [rax + aml_node.value + aml_value.type], AML_T_ALIAS
    jne .have
    mov rax, [rax + aml_node.value + aml_value.data]
.have:
    mov r12, rax
    add r13, 4
    dec r14d
    jnz .seg
.existing:
    mov rax, r12
    mov edx, 1
    jmp .out
.missing:
    cmp r14d, 1                         ; only the last segment may be new
    jne .fail
    mov rdi, r12
    mov esi, [r13]
    call aml_node_new
    test rax, rax
    jz .fail
    xor edx, edx
    jmp .out
.fail:
    xor eax, eax
    xor edx, edx
.out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_ns_init — the root and the names that exist before any table:
;   \_GPE \_PR_ \_SB_ \_SI_ \_TZ_  scopes
;   \_GL_  the global lock (a mutex)
;   \_OSI  built-in method, one argument
;   \_REV  2: the integer width and revision this interpreter follows
;   \_OS_  this OS's name
; Output: EAX = 0, or -AML_ENOMEM
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
aml_ns_init:
    push rbx
    xor edi, edi
    mov esi, AML_SEG('\', '_', '_', '_')
    call aml_node_new
    test rax, rax
    jz .oom
    mov [rel aml_root], rax
    mov byte [rax + aml_node.value + aml_value.type], AML_T_SCOPE

%macro AML_PREDEF 2
    mov rdi, [rel aml_root]
    mov esi, %1
    call aml_node_new
    test rax, rax
    jz .oom
    mov byte [rax + aml_node.value + aml_value.type], %2
%endmacro
    AML_PREDEF AML_SEG('_','G','P','E'), AML_T_SCOPE
    AML_PREDEF AML_SEG('_','P','R','_'), AML_T_SCOPE
    AML_PREDEF AML_SEG('_','S','B','_'), AML_T_DEVICE
    AML_PREDEF AML_SEG('_','S','I','_'), AML_T_SCOPE
    AML_PREDEF AML_SEG('_','T','Z','_'), AML_T_SCOPE
    AML_PREDEF AML_SEG('_','G','L','_'), AML_T_MUTEX
    AML_PREDEF AML_SEG('_','O','S','I'), AML_T_METHOD
    mov rbx, rax
    or dword [rbx + aml_node.flags], AML_NODE_NATIVE
    lea rcx, [rel aml_native_osi]
    mov [rbx + aml_node.x0], rcx
    mov byte [rbx + aml_node.x2], 1
    AML_PREDEF AML_SEG('_','R','E','V'), AML_T_INTEGER
    mov qword [rax + aml_node.value + aml_value.data], 2
    AML_PREDEF AML_SEG('_','O','S','_'), AML_T_STRING
    lea rcx, [rel aml_os_name]
    mov [rax + aml_node.value + aml_value.data], rcx
    mov dword [rax + aml_node.value + aml_value.len], AML_OS_NAME_LEN
%unmacro AML_PREDEF 2
    xor eax, eax
    pop rbx
    ret
.oom:
    mov eax, -AML_ENOMEM
    pop rbx
    ret

%endif ; LIB_IO_ACPI_AML_NS_ASM
