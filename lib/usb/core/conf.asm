; =============================================================================
; Utkarsha OS — lib/usb/core/conf.asm — USB policy settings
; =============================================================================
;   usb_conf_apply(text, len)   settings from the text of /conf/usb/usb.conf:
;                               one "name = value" a line, # starts a
;                               comment, spaces and tabs anywhere
;
;   new_keyboard_check = on | off   (also yes/no, true/false, 1/0)
;
; EAX = settings applied. A line it does not understand is counted in
; usb_conf_rejected and changes nothing, so a typo cannot turn a check off.
; The kernel has no filesystem mounted at boot yet: whoever mounts /conf
; calls this with the file's text.
; =============================================================================

%ifndef LIB_USB_CORE_CONF_ASM
%define LIB_USB_CORE_CONF_ASM

section .bss
global usb_conf_rejected
usb_conf_rejected:  resd 1

section .rodata
usb_conf_nkc:       db "new_keyboard_check", 0
usb_conf_on:        db "on", 0, "yes", 0, "true", 0, "1", 0, 0
usb_conf_off:       db "off", 0, "no", 0, "false", 0, "0", 0, 0

section .text

; usb_conf_word — does the word at RSI (R8 bytes) equal the NUL-terminated
; RDI, ignoring case? ZF = 1 (je) when it does
usb_conf_word:
    xor ecx, ecx
.char:
    mov al, [rdi + rcx]
    test al, al
    jz .end
    cmp rcx, r8
    jae .differ
    mov dl, [rsi + rcx]
    cmp dl, 'A'
    jb .cmp
    cmp dl, 'Z'
    ja .cmp
    or dl, 0x20
.cmp:
    cmp al, dl
    jne .differ
    inc ecx
    jmp .char
.end:
    cmp rcx, r8                         ; and nothing more of the word
    ret
.differ:
    test esp, esp                       ; ZF = 0
    ret

; usb_conf_list — is the word at RSI (R8) one of the list at RDI (words,
; each NUL-ended, the list ended by an empty one)? ZF = 1 when it is
usb_conf_list:
.word:
    cmp byte [rdi], 0
    je .no
    push rdi
    call usb_conf_word
    pop rdi
    je .yes
.skip:
    inc rdi
    cmp byte [rdi - 1], 0
    jne .skip
    jmp .word
.no:
    test esp, esp
.yes:
    ret

; -----------------------------------------------------------------------------
; usb_conf_apply — RDI = text, ESI = its length → EAX = settings applied
; -----------------------------------------------------------------------------
global usb_conf_apply
usb_conf_apply:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi                       ; length
    xor r13d, r13d                      ; position
    xor ebp, ebp                        ; applied
.line:
    cmp r13d, r12d
    jae .done
    ; the line: R13 .. R14 (the newline or the end), a comment cut off
    mov r14d, r13d
.find_end:
    cmp r14d, r12d
    jae .have_line
    cmp byte [rbx + r14], 0x0A
    je .have_line
    inc r14d
    jmp .find_end
.have_line:
    mov r15d, r13d
.comment:
    cmp r15d, r14d
    jae .no_comment
    cmp byte [rbx + r15], '#'
    je .no_comment
    inc r15d
    jmp .comment
.no_comment:
    ; R15 = where the line's content ends
    call .parse
    lea r13d, [r14d + 1]
    jmp .line
.done:
    mov eax, ebp
    add rsp, 8
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; one line: R13 .. R15 of RBX; blank lines are fine, anything else that is
; not a known setting is rejected
.parse:
    push r13
    call .blank
    cmp r13d, r15d
    jae .parsed                         ; blank or only a comment
    ; the name
    mov r8d, r13d
.name:
    cmp r8d, r15d
    jae .reject
    mov al, [rbx + r8]
    cmp al, '='
    je .name_end
    cmp al, ' '
    je .name_end
    cmp al, 9
    je .name_end
    inc r8d
    jmp .name
.name_end:
    mov r9d, r8d                        ; just past the name
    lea rsi, [rbx + r13]
    sub r8d, r13d
    lea rdi, [rel usb_conf_nkc]
    call usb_conf_word
    jne .reject
    mov r13d, r9d
    call .blank
    cmp r13d, r15d
    jae .reject
    cmp byte [rbx + r13], '='
    jne .reject
    inc r13d
    call .blank
    ; the value, to the end less trailing blanks and a carriage return
    mov r8d, r15d
.trim:
    cmp r8d, r13d
    jbe .reject
    mov al, [rbx + r8 - 1]
    cmp al, ' '
    je .trimmed
    cmp al, 9
    je .trimmed
    cmp al, 0x0D
    jne .value
.trimmed:
    dec r8d
    jmp .trim
.value:
    lea rsi, [rbx + r13]
    sub r8d, r13d
    lea rdi, [rel usb_conf_on]
    call usb_conf_list
    je .on
    lea rdi, [rel usb_conf_off]
    call usb_conf_list
    jne .reject
    mov dword [rel usb_new_keyboard_check], 0
    inc ebp
    jmp .parsed
.on:
    mov dword [rel usb_new_keyboard_check], 1
    inc ebp
    jmp .parsed
.reject:
    inc dword [rel usb_conf_rejected]
.parsed:
    pop r13
    ret

; R13 past spaces, tabs and carriage returns, up to R15
.blank:
    cmp r13d, r15d
    jae .blank_out
    mov al, [rbx + r13]
    cmp al, ' '
    je .blank_skip
    cmp al, 9
    je .blank_skip
    cmp al, 0x0D
    jne .blank_out
.blank_skip:
    inc r13d
    jmp .blank
.blank_out:
    ret

%endif ; LIB_USB_CORE_CONF_ASM
