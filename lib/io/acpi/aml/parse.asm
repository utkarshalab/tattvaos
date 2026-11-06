; =============================================================================
; Utkarsha OS — lib/io/acpi/aml/parse.asm
; =============================================================================
; Reading bytecode. Every read is checked against the end of the term list
; it belongs to (aml_frame.end), so a truncated or lying table cannot make
; the interpreter read past it. R15 = the current frame throughout.
; =============================================================================

%ifndef LIB_IO_ACPI_AML_PARSE_ASM
%define LIB_IO_ACPI_AML_PARSE_ASM

section .text

; -----------------------------------------------------------------------------
; aml_byte — the next byte
; Output: EAX = the byte and CF = 0; or CF = 1 at the end
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
aml_byte:
    mov rcx, [r15 + aml_frame.ip]
    cmp rcx, [r15 + aml_frame.end]
    jae .end
    movzx eax, byte [rcx]
    inc rcx
    mov [r15 + aml_frame.ip], rcx
    clc
    ret
.end:
    stc
    ret

; -----------------------------------------------------------------------------
; aml_peek — the next byte without taking it
; Output: EAX = the byte, or -1 at the end
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
aml_peek:
    mov rcx, [r15 + aml_frame.ip]
    cmp rcx, [r15 + aml_frame.end]
    jae .end
    movzx eax, byte [rcx]
    ret
.end:
    mov eax, -1
    ret

; -----------------------------------------------------------------------------
; aml_bytes — take N bytes
; Input:  EDI = N
; Output: RAX = where they start and CF = 0; or CF = 1 when fewer remain
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
aml_bytes:
    mov rax, [r15 + aml_frame.ip]
    mov rcx, [r15 + aml_frame.end]
    sub rcx, rax
    mov edx, edi
    cmp rcx, rdx
    jb .short
    add rdx, rax
    mov [r15 + aml_frame.ip], rdx
    clc
    ret
.short:
    stc
    ret

; -----------------------------------------------------------------------------
; aml_pkglen_value — a PkgLength as a number (field lists use it this way)
; Output: RAX = the length and CF = 0; CF = 1 when truncated
; Clobbers: RAX, RCX, RDX, RDI
; -----------------------------------------------------------------------------
aml_pkglen_value:
    call aml_byte
    jc .out
    mov edx, eax
    shr edx, 6                          ; following bytes: 0-3
    test edx, edx
    jnz .long
    and eax, 0x3F
    clc
    ret
.long:
    mov edi, eax
    and edi, 0x0F                       ; low four bits of the length
    push rbx
    push r12
    mov ebx, edx
    mov r12d, 4                         ; shift for the next byte
.more:
    call aml_byte
    jc .bad
    mov ecx, r12d
    shl eax, cl
    or edi, eax
    add r12d, 8
    dec ebx
    jnz .more
    mov eax, edi
    pop r12
    pop rbx
    clc
    ret
.bad:
    pop r12
    pop rbx
    stc
.out:
    ret

; -----------------------------------------------------------------------------
; aml_pkglen — a PkgLength as the end of its package
; The length counts from the PkgLength's first byte; the end must lie
; inside the current term list.
; Output: RAX = the end and CF = 0; CF = 1 when malformed
; Clobbers: RAX, RCX, RDX, RDI, R8
; -----------------------------------------------------------------------------
aml_pkglen:
    mov r8, [r15 + aml_frame.ip]
    call aml_pkglen_value
    jc .out
    add rax, r8
    cmp rax, [r15 + aml_frame.ip]
    jb .bad                             ; shorter than its own length bytes
    cmp rax, [r15 + aml_frame.end]
    ja .bad
    clc
    ret
.bad:
    stc
.out:
    ret

; -----------------------------------------------------------------------------
; aml_is_lead — whether a byte starts a NameString
; Input:  EAX = byte
; Output: ZF = 1 (je) when it does
; Clobbers: nothing but flags
; -----------------------------------------------------------------------------
aml_is_lead:
    cmp eax, '\'
    je .out
    cmp eax, '^'
    je .out
    cmp eax, '_'
    je .out
    cmp eax, 0x2E                       ; DualNamePrefix
    je .out
    cmp eax, 0x2F                       ; MultiNamePrefix
    je .out
    cmp eax, 'A'
    jb .no
    cmp eax, 'Z'
    ja .no
    cmp eax, eax                        ; ZF = 1
    ret
.no:
    cmp eax, -2                         ; ZF = 0 (EAX is a byte)
.out:
    ret

; -----------------------------------------------------------------------------
; aml_name — read a NameString
; Input:  RDI = aml_path* to fill
; Output: CF = 0, or CF = 1 when malformed
; Clobbers: RAX, RCX, RDX, RDI, RSI
; -----------------------------------------------------------------------------
aml_name:
    mov rsi, rdi
    mov qword [rsi], 0
    mov qword [rsi + 8], 0
    call aml_peek
    cmp eax, '\'
    jne .carets
    mov byte [rsi + aml_path.root], 1
    call aml_byte
    jmp .path
.carets:
    call aml_peek
    cmp eax, '^'
    jne .path
    inc byte [rsi + aml_path.carets]
    call aml_byte
    jmp .carets
.path:
    call aml_byte
    jc .bad
    test eax, eax
    jz .ok                              ; NullName: no segments
    cmp eax, 0x2E
    je .dual
    cmp eax, 0x2F
    je .multi
    ; one segment; its first byte is already taken
    dec qword [r15 + aml_frame.ip]
    mov edx, 1
    jmp .segs
.dual:
    mov edx, 2
    jmp .segs
.multi:
    call aml_byte
    jc .bad
    mov edx, eax
    test edx, edx
    jz .bad
.segs:
    mov [rsi + aml_path.count], dl
    lea edi, [rdx * 4]
    call aml_bytes
    jc .bad
    mov [rsi + aml_path.segs], rax
.ok:
    clc
    ret
.bad:
    stc
    ret

%endif ; LIB_IO_ACPI_AML_PARSE_ASM
