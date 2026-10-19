; ============================================================================
; Verifier Hooks — RSO (Register Ownership) Verification Integration
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

section .text

; ---------------------------------------------------------------------------
; verifier_init
; ---------------------------------------------------------------------------
global verifier_init
verifier_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.verifier], 0
    mov qword [rbx + Server.arena], r12

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; verifier_verify_client
;   Verify client binary with RSO (Register Ownership) rules
;   IN:  rdi = server*, rsi = client_image_ptr, rdx = image_size
;   OUT: rax = 1 if verified, 0 if failed, negative error
; ---------------------------------------------------------------------------
global verifier_verify_client
verifier_verify_client:
    PROLOGUE_SAVE rbx, r12, r13, r14
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    cmp r13, 64
    jb .fail
    mov eax, [r12]
    cmp eax, 0x464C457F
    jne .fail
    cmp byte [r12 + 4], 2       ; ELFCLASS64
    jne .fail
    cmp byte [r12 + 5], 1       ; little endian
    jne .fail
    cmp byte [r12 + 6], 1       ; ELF version
    jne .fail
    cmp word [r12 + 18], 62     ; x86-64
    jne .fail
    cmp word [r12 + 52], 64
    jb .fail
    movzx eax, word [r12 + 54]
    cmp eax, 56
    jb .fail
    movzx ecx, word [r12 + 56]
    test ecx, ecx
    jz .fail
    imul rax, rcx
    jo .fail
    mov r14, [r12 + 32]
    add rax, r14
    jc .fail
    cmp rax, r13
    ja .fail

    add r14, r12
    movzx r15d, word [r12 + 56]
    mov qword [rsp], 0          ; executable segment found
    mov rax, [r12 + 24]
    mov [rsp + 8], rax          ; ELF entry point
.ph_loop:
    cmp dword [r14], 1          ; PT_LOAD
    jne .next_ph
    mov rax, [r14 + 32]         ; p_filesz
    cmp rax, [r14 + 40]         ; p_memsz
    ja .fail
    add rax, [r14 + 8]          ; p_offset + p_filesz
    jc .fail
    cmp rax, r13
    ja .fail
    mov rax, [r14 + 16]
    add rax, [r14 + 40]
    jc .fail
    mov rcx, [r14 + 48]
    test rcx, rcx
    jz .align_ok
    mov rax, rcx
    dec rax
    test rax, rcx
    jnz .fail
    mov rax, [r14 + 16]
    sub rax, [r14 + 8]
    dec rcx
    test rax, rcx
    jnz .fail
.align_ok:
    mov eax, [r14 + 4]
    and eax, 3                   ; PF_X | PF_W is forbidden
    cmp eax, 3
    je .fail
    test dword [r14 + 4], 1
    jz .next_ph
    mov qword [rsp], 1
    mov rax, [rsp + 8]
    cmp rax, [r14 + 16]
    jb .scan
    mov rcx, [r14 + 16]
    add rcx, [r14 + 40]
    cmp rax, rcx
    jae .scan
    mov qword [rsp + 8], 0
.scan:
    mov rdi, rbx
    mov rsi, r12
    add rsi, [r14 + 8]
    mov rdx, [r14 + 32]
    call verifier_check_instruction
    test rax, rax
    jz .fail
.next_ph:
    movzx eax, word [r12 + 54]
    add r14, rax
    dec r15
    jnz .ph_loop
    cmp qword [rsp], 1
    jne .fail
    cmp qword [rsp + 8], 0
    jne .fail

    mov rax, 1
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.fail:
    xor rax, rax
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; verifier_check_instruction
;   Check single instruction for RSO compliance
; ---------------------------------------------------------------------------
global verifier_check_instruction
verifier_check_instruction:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    test r13, r13
    jz .safe
.scan_byte:
    movzx eax, byte [r12]
    cmp al, 0xF4                ; HLT
    je .unsafe
    cmp al, 0xFA                ; CLI
    je .unsafe
    cmp al, 0xFB                ; STI
    je .unsafe
    cmp al, 0xCF                ; IRET
    je .unsafe
    cmp al, 0xCD                ; INT imm8
    je .unsafe
    cmp al, 0x9A                ; far CALL
    je .unsafe
    cmp al, 0xEA                ; far JMP
    je .unsafe
    cmp al, 0xE4
    jb .two_byte
    cmp al, 0xEF                ; IN/OUT family
    jbe .unsafe
.two_byte:
    cmp al, 0x0F
    jne .next
    cmp r13, 2
    jb .unsafe
    movzx eax, byte [r12 + 1]
    cmp al, 0x00                ; descriptor-table group
    je .unsafe
    cmp al, 0x01                ; system-instruction group
    je .unsafe
    cmp al, 0x20                ; MOV from control/debug register
    jb .msr
    cmp al, 0x23
    jbe .unsafe
.msr:
    cmp al, 0x30                ; WRMSR
    je .unsafe
    cmp al, 0x32                ; RDMSR
    je .unsafe
    cmp al, 0x34                ; SYSENTER
    je .unsafe
    cmp al, 0x35                ; SYSEXIT
    je .unsafe
    inc r12
    dec r13
.next:
    inc r12
    dec r13
    jnz .scan_byte
.safe:
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.unsafe:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; verifier_register_client
;   Register verified client
; ---------------------------------------------------------------------------
global verifier_register_client
verifier_register_client:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Mark client as verified
    mov byte [r12 + Client.verified], 1

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; verifier_is_verified
; ---------------------------------------------------------------------------
global verifier_is_verified
verifier_is_verified:
    PROLOGUE
    ASSERT_PTR rdi
    movzx rax, byte [rdi + Client.verified]
    leave
    ret

section .data
global verifier_version
verifier_version: dq 0x010000
