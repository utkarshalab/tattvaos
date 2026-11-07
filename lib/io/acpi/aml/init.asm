; =============================================================================
; Utkarsha OS — lib/io/acpi/aml/init.asm
; =============================================================================
; After the tables are loaded:
;   aml_run_reg      tell the firmware an address space now has a handler
;                    (_REG (space, 1) for every device with such a region)
;   aml_initialize   \_SB._INI, then every device's _STA and _INI, depth
;                    first, in definition order; an absent device's
;                    children are skipped, a functional one's are not
; And for drivers:
;   aml_device_status  the _STA bits found by aml_initialize
;   aml_match_id       whether a device's _HID or _CID is an ID ("PNP0C50")
;   aml_find_device    the Nth present device with an ID
;
; A failing _STA, _INI or _REG is counted and skipped: one broken device
; does not stop the rest (ROADMAP.md §1, reliability).
; =============================================================================

%ifndef LIB_IO_ACPI_AML_INIT_ASM
%define LIB_IO_ACPI_AML_INIT_ASM

%define AML_STA_PRESENT     (1 << 0)
%define AML_STA_FUNCTIONAL  (1 << 3)
%define AML_STA_DEFAULT     0x0F        ; no _STA: present and working
%define AML_STA_KNOWN       (1 << 32)   ; device x2: status was evaluated
%define AML_MAX_REG_DEVICES 256
%define AML_NO_CHILD        1           ; aml_eval_child: nothing by that name

section .bss
alignb 8
global aml_init_devices
aml_init_devices:   resd 1          ; devices whose _STA was read
global aml_init_inis
aml_init_inis:      resd 1          ; _INI methods run
global aml_init_errors
aml_init_errors:    resd 1          ; _STA, _INI or _REG that failed
aml_find_left:      resd 1          ; aml_find_device: matches still to skip
alignb 8
aml_find_id:        resq 1          ; aml_find_device: the ID
aml_reg_space:      resq 1          ; aml_run_reg: the space
aml_reg_done:       resq 1          ; aml_run_reg: devices already called
aml_reg_count:      resd 1
alignb 16
aml_walk_frame:     resb aml_frame_size ; the walk's frame: temporary memory
                                    ; is released between devices

section .text

; -----------------------------------------------------------------------------
; aml_eval_child — evaluate a child of a node by name: call it with no
;                  arguments if it is a method, read it otherwise
; Input:  RDI = node, ESI = child name, RDX = destination value*
; Output: EAX = 0; AML_NO_CHILD (positive) when there is no such child;
;         or a negative error from evaluating it
; Needs R15 = a frame.
; -----------------------------------------------------------------------------
aml_eval_child:
    push rbx
    push r12
    sub rsp, 8
    mov r12, rdx
    call aml_child
    test rax, rax
    jz .missing
    mov rbx, rax
    cmp byte [rbx + aml_node.value + aml_value.type], AML_T_ALIAS
    jne .resolved
    mov rbx, [rbx + aml_node.value + aml_value.data]
.resolved:
    cmp byte [rbx + aml_node.value + aml_value.type], AML_T_METHOD
    je .call
    mov rdi, rbx
    mov rsi, r12
    call aml_read_node_value
    jmp .out
.call:
    mov edi, AML_ARGS * aml_value_size
    call aml_talloc
    test rax, rax
    jz .oom
    mov rdi, rbx
    mov rsi, rax
    mov rdx, r12
    call aml_call
    jmp .out
.missing:
    mov eax, AML_NO_CHILD
    jmp .out
.oom:
    mov eax, -AML_ENOMEM
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_eval_child_of — aml_eval_child from outside the interpreter: fresh
;                     temporary memory and a frame of its own
; Input:  RDI = node, ESI = child name, RDX = destination value*
; Output: EAX = 0; AML_NO_CHILD (positive) when there is no such child; or
;         a negative error
; -----------------------------------------------------------------------------
global aml_eval_child_of
aml_eval_child_of:
    push rbx
    push r12
    push r13
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    AML_BEGIN
    call aml_top_frame
    test rax, rax
    jz .oom
    mov r15, rax
    mov rdi, rbx
    mov esi, r12d
    mov rdx, r13
    call aml_eval_child
    jmp .out
.oom:
    mov eax, -AML_ENOMEM
.out:
    add rsp, 8
    pop r15
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_is_device — whether a node is something _STA and _INI apply to
; Input:  RDI = node
; Output: ZF = 1 (je) for a device, processor or thermal zone
; -----------------------------------------------------------------------------
aml_is_device:
    movzx eax, byte [rdi + aml_node.value + aml_value.type]
    cmp eax, AML_T_DEVICE
    je .out
    cmp eax, AML_T_PROCESSOR
    je .out
    cmp eax, AML_T_THERMAL
.out:
    ret

; -----------------------------------------------------------------------------
; aml_initialize — run \_SB._INI, then _STA and _INI for every device
; Output: EAX = 0 (failures are counted in aml_init_errors)
; -----------------------------------------------------------------------------
global aml_initialize
aml_initialize:
    push rbx
    push r15
    sub rsp, 24
    AML_BEGIN
    xor eax, eax
    mov [rel aml_init_devices], eax
    mov [rel aml_init_inis], eax
    mov [rel aml_init_errors], eax
    lea rdi, [rel aml_walk_frame]
    mov ecx, aml_frame_size
    xor eax, eax
    rep stosb
    lea r15, [rel aml_walk_frame]
    mov rax, [rel aml_root]
    mov [r15 + aml_frame.scope], rax
    ; \_SB._INI first
    mov rdi, [rel aml_root]
    mov esi, AML_SEG('_','S','B','_')
    call aml_child
    test rax, rax
    jz .walk
    mov rdi, rax
    mov esi, AML_SEG('_','I','N','I')
    mov rdx, rsp
    call aml_eval_child
    cmp eax, AML_NO_CHILD
    je .walk
    inc dword [rel aml_init_inis]
    test eax, eax
    jz .walk
    inc dword [rel aml_init_errors]
.walk:
    call aml_temp_reset
    mov rdi, [rel aml_root]
    call aml_init_walk
    xor eax, eax
    add rsp, 24
    pop r15
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_init_walk — _STA and _INI for every device below a node
; Input:  RDI = node; R15 = a frame
; Temporary memory is released after each device: nothing here keeps it.
; -----------------------------------------------------------------------------
aml_init_walk:
    push rbx
    push r12
    sub rsp, 24                         ; a value, padding
    mov rbx, [rdi + aml_node.child]
.child:
    test rbx, rbx
    jz .out
    mov rdi, rbx
    call aml_is_device
    jne .scope
    cmp dword [rbx + aml_node.name], AML_SEG('_','S','B','_')
    jne .device
    mov rax, [rbx + aml_node.parent]
    cmp rax, [rel aml_root]
    je .scope                           ; \_SB: its _INI ran first
.device:
    inc dword [rel aml_init_devices]
    ; _STA, or present and working when there is none
    mov r12d, AML_STA_DEFAULT
    mov rdi, rbx
    mov esi, AML_SEG('_','S','T','A')
    mov rdx, rsp
    call aml_eval_child
    cmp eax, AML_NO_CHILD
    je .status
    test eax, eax
    jnz .sta_failed
    mov rdi, rsp
    xor esi, esi
    call aml_to_int
    test eax, eax
    jnz .sta_failed
    mov r12d, edx
    jmp .status
.sta_failed:
    inc dword [rel aml_init_errors]
    xor r12d, r12d                      ; a device that cannot say is absent
.status:
    mov rax, AML_STA_KNOWN
    or rax, r12
    mov [rbx + aml_node.x2], rax
    test r12d, AML_STA_PRESENT
    jz .absent
    mov rdi, rbx
    mov esi, AML_SEG('_','I','N','I')
    mov rdx, rsp
    call aml_eval_child
    cmp eax, AML_NO_CHILD
    je .children
    inc dword [rel aml_init_inis]
    test eax, eax
    jz .children
    inc dword [rel aml_init_errors]
    jmp .children
.absent:
    test r12d, AML_STA_FUNCTIONAL       ; not there, but its children may be
    jz .next
.children:
    call aml_temp_reset
.scope:
    mov rdi, rbx
    call aml_init_walk
.next:
    call aml_temp_reset
    mov rbx, [rbx + aml_node.next]
    jmp .child
.out:
    add rsp, 24
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_device_status — the _STA bits aml_initialize found
; Input:  RDI = device node
; Output: EAX = the bits, or -1 when the device was never evaluated
; -----------------------------------------------------------------------------
global aml_device_status
aml_device_status:
    mov rax, [rdi + aml_node.x2]
    mov rcx, AML_STA_KNOWN
    test rax, rcx
    jz .unknown
    ret
.unknown:
    mov eax, -1
    ret

; -----------------------------------------------------------------------------
; aml_id_text — an ID value as text: strings as they are, compressed EISA
;               integers as their seven characters ("PNP0C50")
; Input:  RDI = value*, RSI = 16-byte buffer for the text
; Output: EAX = 0, or -AML_ETYPE for any other value
; -----------------------------------------------------------------------------
aml_id_text:
    movzx eax, byte [rdi + aml_value.type]
    cmp eax, AML_T_STRING
    je .string
    cmp eax, AML_T_INTEGER
    jne .type
    ; EISA ID: stored byte-swapped; three 5-bit letters, four hex digits
    mov eax, [rdi + aml_value.data]
    bswap eax
    mov edx, eax
    shr edx, 26
    and edx, 0x1F
    add edx, 0x40
    mov [rsi], dl
    mov edx, eax
    shr edx, 21
    and edx, 0x1F
    add edx, 0x40
    mov [rsi + 1], dl
    mov edx, eax
    shr edx, 16
    and edx, 0x1F
    add edx, 0x40
    mov [rsi + 2], dl
    mov ecx, 12
    lea r8, [rsi + 3]
.hex:
    mov edx, eax
    shr edx, cl
    and edx, 0x0F
    add edx, '0'
    cmp edx, '9'
    jbe .digit
    add edx, 'A' - '9' - 1
.digit:
    mov [r8], dl
    inc r8
    sub ecx, 4
    jns .hex
    mov byte [r8], 0
    xor eax, eax
    ret
.string:
    mov ecx, [rdi + aml_value.len]
    cmp ecx, 15
    jbe .copy
    mov ecx, 15
.copy:
    mov r8, [rdi + aml_value.data]
    xor edx, edx
.byte:
    cmp edx, ecx
    jae .end
    mov al, [r8 + rdx]
    mov [rsi + rdx], al
    inc edx
    jmp .byte
.end:
    mov byte [rsi + rdx], 0
    xor eax, eax
    ret
.type:
    mov eax, -AML_ETYPE
    ret

; -----------------------------------------------------------------------------
; aml_id_equal — compare an ID value with NUL-terminated text
; Input:  RDI = value*, RSI = text
; Output: EAX = 1 when equal, else 0
; -----------------------------------------------------------------------------
aml_id_equal:
    push rbx
    sub rsp, 16
    mov rbx, rsi
    mov rsi, rsp
    call aml_id_text
    test eax, eax
    jnz .no
    xor ecx, ecx
.cmp:
    mov al, [rsp + rcx]
    cmp al, [rbx + rcx]
    jne .no
    test al, al
    jz .yes
    inc ecx
    cmp ecx, 16
    jb .cmp
.no:
    xor eax, eax
    jmp .out
.yes:
    mov eax, 1
.out:
    add rsp, 16
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_match_id — whether a device's _HID, or one of its _CID IDs, is an ID
; Input:  RDI = device node, RSI = ID text
; Output: EAX = 1 or 0
; -----------------------------------------------------------------------------
global aml_match_id
aml_match_id:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    AML_BEGIN
    call aml_top_frame
    test rax, rax
    jz .no
    mov r15, rax
    mov rdi, rbx
    mov esi, AML_SEG('_','H','I','D')
    mov rdx, rsp
    call aml_eval_child
    test eax, eax
    jnz .cid
    mov rdi, rsp
    mov rsi, r12
    call aml_id_equal
    test eax, eax
    jnz .out
.cid:
    mov rdi, rbx
    mov esi, AML_SEG('_','C','I','D')
    mov rdx, rsp
    call aml_eval_child
    test eax, eax
    jnz .no
    cmp byte [rsp + aml_value.type], AML_T_PACKAGE
    je .package
    mov rdi, rsp
    mov rsi, r12
    call aml_id_equal
    jmp .out
.package:
    mov r13, [rsp + aml_value.data]
    mov r14d, [rsp + aml_value.len]
.element:
    test r14d, r14d
    jz .no
    mov rdi, r13
    mov rsi, r12
    call aml_id_equal
    test eax, eax
    jnz .out
    add r13, aml_value_size
    dec r14d
    jmp .element
.no:
    xor eax, eax
.out:
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_find_device — the Nth present device with an ID (after aml_initialize)
; Input:  RDI = ID text, ESI = N (0 for the first)
; Output: RAX = device node, or 0
; -----------------------------------------------------------------------------
global aml_find_device
aml_find_device:
    sub rsp, 8
    mov [rel aml_find_id], rdi
    mov [rel aml_find_left], esi
    mov rdi, [rel aml_root]
    call aml_find_walk
    add rsp, 8
    ret

aml_find_walk:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, [rdi + aml_node.child]
.child:
    test rbx, rbx
    jz .none
    mov rdi, rbx
    call aml_is_device
    jne .scope
    mov rdi, rbx
    call aml_device_status
    test eax, AML_STA_PRESENT           ; -1 (never evaluated) passes too
    jz .skip_children                   ; absent: so are its children,
    mov rdi, rbx                        ; unless functional
    mov rsi, [rel aml_find_id]
    call aml_match_id
    test eax, eax
    jz .scope
    cmp dword [rel aml_find_left], 0
    je .found
    dec dword [rel aml_find_left]
.scope:
    mov rdi, rbx
    call aml_find_walk
    test rax, rax
    jnz .out
.next:
    mov rbx, [rbx + aml_node.next]
    jmp .child
.skip_children:
    mov rdi, rbx
    call aml_device_status
    test eax, AML_STA_FUNCTIONAL
    jnz .scope
    jmp .next
.found:
    mov rax, rbx
    jmp .out
.none:
    xor eax, eax
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_run_reg — a handler for an address space exists now: call _REG
;               (space, 1) once on each device that has a region in it
; Input:  EDI = region space
; Output: EAX = 0 (failures are counted in aml_init_errors)
; -----------------------------------------------------------------------------
global aml_run_reg
aml_run_reg:
    push rbx
    push r15
    sub rsp, 8
    mov ebx, edi
    AML_BEGIN
    mov [rel aml_reg_space], rbx
    mov dword [rel aml_reg_count], 0
    mov edi, AML_MAX_REG_DEVICES * 8
    call aml_talloc
    test rax, rax
    jz .oom
    mov [rel aml_reg_done], rax
    call aml_top_frame
    test rax, rax
    jz .oom
    mov r15, rax
    mov rdi, [rel aml_root]
    call aml_reg_walk
    xor eax, eax
    jmp .out
.oom:
    mov eax, -AML_ENOMEM
.out:
    add rsp, 8
    pop r15
    pop rbx
    ret

aml_reg_walk:
    push rbx
    push r12
    push r13
    sub rsp, 16                         ; the arguments live in temp memory
    mov rbx, [rdi + aml_node.child]
.child:
    test rbx, rbx
    jz .out
    cmp byte [rbx + aml_node.value + aml_value.type], AML_T_REGION
    jne .scope
    movzx eax, byte [rbx + aml_node.x2]
    cmp rax, [rel aml_reg_space]
    jne .next
    mov r12, [rbx + aml_node.parent]
    ; called for this device already?
    mov rcx, [rel aml_reg_done]
    mov edx, [rel aml_reg_count]
.seen:
    test edx, edx
    jz .call
    dec edx
    cmp [rcx + rdx * 8], r12
    je .next
    jmp .seen
.call:
    mov edx, [rel aml_reg_count]
    cmp edx, AML_MAX_REG_DEVICES
    jae .next
    mov [rcx + rdx * 8], r12
    inc dword [rel aml_reg_count]
    mov rdi, r12
    mov esi, AML_SEG('_','R','E','G')
    call aml_child
    test rax, rax
    jz .next
    cmp byte [rax + aml_node.value + aml_value.type], AML_T_METHOD
    jne .next
    mov r13, rax
    mov edi, AML_ARGS * aml_value_size + aml_value_size
    call aml_talloc
    test rax, rax
    jz .failed
    mov qword [rax], 0
    mov byte [rax + aml_value.type], AML_T_INTEGER
    mov rcx, [rel aml_reg_space]
    mov [rax + aml_value.data], rcx
    mov byte [rax + aml_value_size + aml_value.type], AML_T_INTEGER
    mov qword [rax + aml_value_size + aml_value.data], 1    ; connected
    mov rdi, r13
    mov rsi, rax
    lea rdx, [rax + AML_ARGS * aml_value_size]
    call aml_call
    test eax, eax
    jz .next
.failed:
    inc dword [rel aml_init_errors]
    jmp .next
.scope:
    mov rdi, rbx
    call aml_reg_walk
.next:
    mov rbx, [rbx + aml_node.next]
    jmp .child
.out:
    add rsp, 16
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_IO_ACPI_AML_INIT_ASM
