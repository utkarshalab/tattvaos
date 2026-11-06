; =============================================================================
; Utkarsha OS — lib/io/acpi/aml/field.asm
; =============================================================================
; Reading and writing fields.
;
; Region fields go through aml_region_fn, one access unit at a time:
;   RDI = region space, RSI = address, EDX = width in bits (8, 16, 32, 64),
;   ECX = 1 to write, 0 to read, R8 = u64* holding or receiving the unit
;   → EAX = 0 or a negative AML_E* error
; With no handler every access fails with -AML_EUNSUPPORTED. The kernel's
; handler is where the sandbox lives: which addresses AML may touch
; (ROADMAP.md decision 3).
;
; Fields up to 64 bits are supported; wider region fields are not yet.
; Buffer fields work on the buffer object itself, so writes are seen by
; everyone holding that buffer.
; =============================================================================

%ifndef LIB_IO_ACPI_AML_FIELD_ASM
%define LIB_IO_ACPI_AML_FIELD_ASM

section .bss
alignb 8
global aml_region_fn
aml_region_fn:      resq 1

section .text

; -----------------------------------------------------------------------------
; aml_field_width — access width in bytes for a field node
; Any access: the smallest width whose aligned unit holds the whole field,
; so registers are read in one access where that is possible.
; Input:  RDI = node
; Output: EAX = 1, 2, 4 or 8
; Clobbers: RAX, RCX, RDX, R8, R9
; -----------------------------------------------------------------------------
aml_field_width:
    mov rax, [rdi + aml_node.x2]
    and eax, 0x0F
    cmp eax, 1
    je .w1
    cmp eax, 2
    je .w2
    cmp eax, 3
    je .w4
    cmp eax, 4
    je .w8
    test eax, eax
    jnz .w1                             ; Buffer access and others: bytes
    ; Any: units are 8 << k bits, so compare first and last unit by shifts
    mov rdx, [rdi + aml_node.x1]
    mov r8d, edx                        ; bit offset
    shr rdx, 32                         ; bit length
    lea rdx, [r8 + rdx - 1]             ; last bit
    mov ecx, 3                          ; log2 of the unit's bits
.try:
    mov rax, r8
    shr rax, cl
    mov r9, rdx
    shr r9, cl
    cmp rax, r9
    je .found
    inc ecx
    cmp ecx, 6
    jbe .try
    jmp .w1
.found:
    sub ecx, 3
    mov eax, 1
    shl eax, cl
    ret
.w1:
    mov eax, 1
.out:
    ret
.w2:
    mov eax, 2
    ret
.w4:
    mov eax, 4
    ret
.w8:
    mov eax, 8
    ret

; -----------------------------------------------------------------------------
; aml_field_unit — read or write one access unit of a field
; Input:  RDI = field node, RSI = unit number, EDX = width in bytes,
;         ECX = 1 write / 0 read, R8 = u64*
; -----------------------------------------------------------------------------
aml_field_unit:
    push rbx
    push r12
    push r13
    push r14
    push rbp
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    mov rbp, r8
    mov rax, [rbx + aml_node.x2]
    test eax, AML_FIELD_INDEX
    jnz .index
    test eax, AML_FIELD_BANK
    jz .region
    ; select the bank first
    mov rdi, [rbx + aml_node.pad]
    mov rsi, [rbx + aml_node.x2]
    shr rsi, 16
    call aml_field_write_int
    test eax, eax
    jnz .out
.region:
    mov rdi, [rbx + aml_node.x0]        ; the region
    test rdi, rdi
    jz .type
    cmp byte [rdi + aml_node.value + aml_value.type], AML_T_REGION
    jne .type
    mov rax, r12
    imul rax, r13                       ; byte offset in the region
    lea rcx, [rax + r13]
    cmp rcx, [rdi + aml_node.x1]
    ja .index_err
    mov rsi, [rdi + aml_node.x0]
    add rsi, rax                        ; address
    movzx edi, byte [rdi + aml_node.x2] ; space
    mov edx, r13d
    shl edx, 3
    mov ecx, r14d
    mov r8, rbp
    mov rax, [rel aml_region_fn]
    test rax, rax
    jz .unsupported
    call rax
    jmp .out
.index:
    ; IndexField: write the byte offset to the index field, then use the
    ; data field
    mov rdi, [rbx + aml_node.x0]
    mov rsi, r12
    imul rsi, r13
    call aml_field_write_int
    test eax, eax
    jnz .out
    mov rdi, [rbx + aml_node.pad]
    test r14d, r14d
    jnz .index_write
    call aml_field_read_int
    test eax, eax
    jnz .out
    mov [rbp], rdx
    jmp .out
.index_write:
    mov rsi, [rbp]
    call aml_field_write_int
    jmp .out
.unsupported:
    mov eax, -AML_EUNSUPPORTED
    jmp .out
.index_err:
    mov eax, -AML_EINDEX
    jmp .out
.type:
    mov eax, -AML_ETYPE
.out:
    add rsp, 16
    pop rbp
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_bits_mask — RAX = a mask of ECX low bits (ECX = 1..64)
; -----------------------------------------------------------------------------
aml_bits_mask:
    mov rax, -1
    cmp ecx, 64
    jae .out
    mov eax, 1
    shl rax, cl
    dec rax
.out:
    ret

; -----------------------------------------------------------------------------
; aml_field_read — a region field's value
; Input:  RDI = field node, RSI = destination value*
; -----------------------------------------------------------------------------
aml_field_read:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 40                         ; unit, result, shift, width, dest
    mov rbx, rdi
    mov [rsp + 32], rsi
    mov rax, [rbx + aml_node.x1]
    mov r12d, eax                       ; bit position
    shr rax, 32
    mov r13d, eax                       ; bits left
    cmp r13d, 64
    ja .unsupported
    test r13d, r13d
    jz .unsupported
    call aml_field_width
    mov [rsp + 24], rax
    mov qword [rsp + 8], 0              ; result
    mov qword [rsp + 16], 0             ; where the next bits go
.unit:
    test r13d, r13d
    jz .done
    mov ebp, [rsp + 24]
    shl ebp, 3                          ; bits per unit
    mov eax, r12d
    xor edx, edx
    div ebp
    mov r14d, eax                       ; unit
    mov r15d, edx                       ; bit inside it
    mov ecx, ebp
    sub ecx, r15d
    cmp ecx, r13d
    jbe .n
    mov ecx, r13d
.n:
    mov ebp, ecx                        ; bits from this unit
    mov qword [rsp], 0
    mov rdi, rbx
    mov esi, r14d
    mov edx, [rsp + 24]
    xor ecx, ecx
    mov r8, rsp
    call aml_field_unit
    test eax, eax
    jnz .out
    mov rax, [rsp]
    mov ecx, r15d
    shr rax, cl
    mov ecx, ebp
    mov rdx, rax
    call aml_bits_mask
    and rdx, rax
    mov ecx, [rsp + 16]
    shl rdx, cl
    or [rsp + 8], rdx
    add [rsp + 16], ebp
    add r12d, ebp
    sub r13d, ebp
    jmp .unit
.done:
    mov rax, [rbx + aml_node.x1]
    shr rax, 32                         ; field bits
    mov rdi, [rsp + 32]
    mov ecx, [rel aml_int_bytes]
    shl ecx, 3
    cmp eax, ecx
    ja .as_buffer
    mov rsi, [rsp + 8]
    call aml_set_int
    xor eax, eax
    jmp .out
.as_buffer:
    ; wider than an integer (a 64-bit field in a 32-bit table): a buffer
    add eax, 7
    shr eax, 3
    mov r12d, eax
    mov edi, 8
    call aml_talloc
    test rax, rax
    jz .oom
    mov rcx, [rsp + 8]
    mov [rax], rcx
    mov rdi, [rsp + 32]
    mov qword [rdi], 0
    mov byte [rdi + aml_value.type], AML_T_BUFFER
    mov [rdi + aml_value.len], r12d
    mov [rdi + aml_value.data], rax
    xor eax, eax
    jmp .out
.oom:
    mov eax, -AML_ENOMEM
    jmp .out
.unsupported:
    mov eax, -AML_EUNSUPPORTED
.out:
    add rsp, 40
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_field_write — write a value to a region field
; Units the field covers only partly follow the field's update rule:
; preserve the other bits (read first), or write them as ones or zeros.
; Input:  RDI = field node, RSI = value*
; -----------------------------------------------------------------------------
aml_field_write:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 40                         ; unit, value, width, bits-of-unit, spare
    mov rbx, rdi
    mov rdi, rsi
    xor esi, esi
    call aml_to_int
    test eax, eax
    jnz .out
    mov [rsp + 8], rdx                  ; bits still to write, lowest first
    mov rax, [rbx + aml_node.x1]
    mov r12d, eax
    shr rax, 32
    mov r13d, eax
    cmp r13d, 64
    ja .unsupported
    test r13d, r13d
    jz .unsupported
    mov rdi, rbx
    call aml_field_width
    mov [rsp + 16], rax
.unit:
    test r13d, r13d
    jz .ok
    mov ebp, [rsp + 16]
    shl ebp, 3
    mov eax, r12d
    xor edx, edx
    div ebp
    mov r14d, eax                       ; unit
    mov r15d, edx                       ; bit inside it
    mov ecx, ebp
    sub ecx, r15d
    cmp ecx, r13d
    jbe .n
    mov ecx, r13d
.n:
    mov [rsp + 24], ecx                 ; bits this unit
    ; the unit's other bits
    xor eax, eax
    cmp ecx, ebp
    je .merge                           ; the whole unit is the field
    mov rax, [rbx + aml_node.x2]
    shr eax, 5
    and eax, 3
    cmp eax, 1
    je .ones
    cmp eax, 2
    je .zeros
    mov qword [rsp], 0                  ; Preserve: read it
    mov rdi, rbx
    mov esi, r14d
    mov edx, [rsp + 16]
    xor ecx, ecx
    mov r8, rsp
    call aml_field_unit
    test eax, eax
    jnz .out
    mov rax, [rsp]
    jmp .merge
.ones:
    mov rax, -1
    jmp .merge
.zeros:
    xor eax, eax
.merge:
    mov r8, rax
    mov ecx, [rsp + 24]
    call aml_bits_mask                  ; RAX = mask of the field's bits
    mov rdx, [rsp + 8]
    and rdx, rax
    mov ecx, r15d
    shl rax, cl
    shl rdx, cl
    not rax
    and r8, rax
    or r8, rdx
    mov [rsp], r8
    mov rdi, rbx
    mov esi, r14d
    mov edx, [rsp + 16]
    mov ecx, 1
    mov r8, rsp
    call aml_field_unit
    test eax, eax
    jnz .out
    mov ecx, [rsp + 24]
    mov rax, [rsp + 8]
    cmp ecx, 64
    jae .all
    shr rax, cl
    jmp .shifted
.all:
    xor eax, eax
.shifted:
    mov [rsp + 8], rax
    add r12d, ecx
    sub r13d, ecx
    jmp .unit
.ok:
    xor eax, eax
    jmp .out
.unsupported:
    mov eax, -AML_EUNSUPPORTED
.out:
    add rsp, 40
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_field_read_int, aml_field_write_int — integer helpers (index and bank
; fields drive other fields with them)
; aml_field_read_int:  RDI = node → EAX = status, RDX = the integer
; aml_field_write_int: RDI = node, RSI = integer → EAX = status
; -----------------------------------------------------------------------------
aml_field_read_int:
    sub rsp, 24
    mov rsi, rsp
    call aml_field_read
    test eax, eax
    jnz .out
    mov rdi, rsp
    xor esi, esi
    call aml_to_int
.out:
    add rsp, 24
    ret

aml_field_write_int:
    push rbx
    sub rsp, 16
    mov rbx, rdi
    mov rdi, rsp
    call aml_set_int
    mov rdi, rbx
    mov rsi, rsp
    call aml_field_write
    add rsp, 16
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_buffield_check — where a buffer field's bits are
; Input:  RDI = buffer field node
; Output: EAX = 0 or error; RSI = buffer bytes, ECX = bit offset,
;         EDX = bit length
; -----------------------------------------------------------------------------
aml_buffield_check:
    mov r8, [rdi + aml_node.x0]         ; the buffer's slot
    cmp byte [r8 + aml_value.type], AML_T_BUFFER
    jne .type
    mov rax, [rdi + aml_node.x1]
    mov ecx, eax
    shr rax, 32
    mov edx, eax
    mov eax, [r8 + aml_value.len]
    shl rax, 3
    lea r9, [rcx + rdx]
    cmp r9, rax
    ja .index
    mov rsi, [r8 + aml_value.data]
    xor eax, eax
    ret
.type:
    mov eax, -AML_ETYPE
    ret
.index:
    mov eax, -AML_EINDEX
    ret

; -----------------------------------------------------------------------------
; aml_buffield_read — a buffer field's value
; Input:  RDI = node, RSI = destination value*
; Up to 64 bits: an integer (a buffer if wider than the integer width).
; Wider, byte-aligned fields: a buffer copy.
; -----------------------------------------------------------------------------
aml_buffield_read:
    push rbx
    push r12
    push r13
    mov rbx, rsi
    call aml_buffield_check
    test eax, eax
    jnz .out
    cmp edx, 64
    ja .wide
    ; bit by bit
    xor r8d, r8d                        ; result
    xor r9d, r9d                        ; bit index
.bit:
    cmp r9d, edx
    jae .bits_done
    lea eax, [rcx + r9]                 ; the bit in the buffer
    mov r10d, eax
    shr r10d, 3
    movzx r11d, byte [rsi + r10]
    and eax, 7
    bt r11d, eax
    jnc .clear
    bts r8, r9
.clear:
    inc r9d
    jmp .bit
.bits_done:
    mov eax, [rel aml_int_bytes]
    shl eax, 3
    cmp edx, eax
    ja .int_as_buffer
    mov rdi, rbx
    mov rsi, r8
    call aml_set_int
    xor eax, eax
    jmp .out
.int_as_buffer:
    mov r12, r8
    lea r13d, [rdx + 7]
    shr r13d, 3
    mov edi, 8
    call aml_talloc
    test rax, rax
    jz .oom
    mov [rax], r12
    jmp .buffer_value
.wide:
    test ecx, 7
    jnz .unsupported
    shr ecx, 3
    add rsi, rcx
    mov r12, rsi
    lea r13d, [rdx + 7]
    shr r13d, 3
    mov edi, r13d
    call aml_talloc
    test rax, rax
    jz .oom
    mov rdi, rax
    mov rsi, r12
    mov ecx, r13d
    rep movsb
.buffer_value:
    mov qword [rbx], 0
    mov byte [rbx + aml_value.type], AML_T_BUFFER
    mov [rbx + aml_value.len], r13d
    mov [rbx + aml_value.data], rax
    xor eax, eax
    jmp .out
.oom:
    mov eax, -AML_ENOMEM
    jmp .out
.unsupported:
    mov eax, -AML_EUNSUPPORTED
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_buffield_write — write a value into a buffer field
; Input:  RDI = node, RSI = value*
; -----------------------------------------------------------------------------
aml_buffield_write:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    call aml_buffield_check
    test eax, eax
    jnz .out
    mov r13, rsi                        ; bytes
    mov r14d, ecx                       ; bit offset
    mov r15d, edx                       ; bit length
    cmp r15d, 64
    ja .wide
    mov rdi, r12
    xor esi, esi
    call aml_to_int
    test eax, eax
    jnz .out
    xor r9d, r9d
.bit:
    cmp r9d, r15d
    jae .ok
    lea eax, [r14 + r9]
    mov r10d, eax
    shr r10d, 3
    and eax, 7
    mov ecx, eax
    mov r11d, 1
    shl r11d, cl                        ; the bit in its byte
    bt rdx, r9
    jc .set
    not r11d
    and [r13 + r10], r11b
    jmp .next
.set:
    or [r13 + r10], r11b
.next:
    inc r9d
    jmp .bit
.wide:
    test r14d, 7
    jnz .unsupported
    mov rdi, rsp
    mov rsi, r12
    call aml_to_buffer
    test eax, eax
    jnz .out
    mov ecx, r14d
    shr ecx, 3
    lea rdi, [r13 + rcx]
    lea ecx, [r15 + 7]
    shr ecx, 3                          ; bytes in the field
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
.ok:
    xor eax, eax
    jmp .out
.unsupported:
    mov eax, -AML_EUNSUPPORTED
.out:
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_IO_ACPI_AML_FIELD_ASM
