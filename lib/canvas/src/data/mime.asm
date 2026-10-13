; ============================================================================
; MIME — MIME Type Handling and Negotiation
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/str.inc"

; struct offsets (hoisted above use)
%define MIME_MAX_TYPES      32
%define MIME_MAX_LEN        128
%define MimeType_size    32

section .text


struc MimeType
    .type:      resq 1
    .subtype:   resq 1
    .params:    resq 1
    .next:      resq 1
endstruc

; ---------------------------------------------------------------------------
; mime_init
; ---------------------------------------------------------------------------
global mime_init
mime_init:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; mime_parse
;   Parse MIME type string (e.g., "text/plain; charset=utf-8")
;   IN:  rdi = string, rsi = length
;   OUT: rax = MimeType*, 0 on error
; ---------------------------------------------------------------------------
global mime_parse
mime_parse:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Find '/'
    mov r13, rbx
    mov r14, r12
.find_slash:
    test r14, r14
    jz .fail
    mov al, [r13]
    cmp al, '/'
    je .found_slash
    inc r13
    dec r14
    jmp .find_slash

.found_slash:
    ; Allocate MimeType
    push r12
    mov rdi, [rsp + 48]  ; arena from caller
    mov rsi, MimeType_size
    call arena_alloc
    pop r12
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Parse type
    mov rdi, rax
    mov rsi, rbx
    mov rdx, r13
    sub rsi, rbx
    call str_dup_arena
    test rax, rax
    jz .oom
    mov [rbx + MimeType.type], rax

    ; Skip '/'
    inc r13
    dec r14

    ; Find ';' or end
    mov r13, r13
    mov r14, r14
.find_semicolon:
    test r14, r14
    jz .parse_subtype_done
    mov al, [r13]
    cmp al, ';'
    je .parse_subtype_done
    inc r13
    dec r14
    jmp .find_semicolon

.parse_subtype_done:
    ; Parse subtype
    push r12
    mov rdi, [rsp + 48]
    mov rsi, r13
    mov rdx, r14
    sub rdx, rsi
    call str_dup_arena
    pop r12
    test rax, rax
    jz .oom
    mov [rbx + MimeType.subtype], rax

    ; Parse parameters
    test r14, r14
    jz .done_params

.parse_params:
    ; Skip ';'
    inc r13
    dec r14
    ; Skip whitespace
.skip_ws:
    test r14, r14
    jz .done_params
    mov al, [r13]
    cmp al, ' '
    jne .parse_param
    cmp al, '\t'
    jne .parse_param
    inc r13
    dec r14
    jmp .skip_ws

.parse_param:
    ; Parse param name
    mov r12, r13
    mov r13, r14
.find_eq:
    test r13, r13
    jz .param_done
    mov al, [r12]
    cmp al, '='
    je .found_eq
    inc r12
    dec r13
    jmp .find_eq

.found_eq:
    ; Param name
    mov rdi, [rsp + 48]
    mov rsi, r12
    mov rdx, r14
    sub rdx, rsi
    call str_dup_arena
    test rax, rax
    jz .oom
    ; TODO: Store param name

    ; Skip '='
    inc r12
    dec r14

    ; Parse param value
    test r14, r14
    jz .param_done
    cmp byte [r12], '"'
    je .quoted_value

.unquoted_value:
    mov r13, r12
.find_semicolon2:
    test r14, r14
    jz .param_done
    mov al, [r12]
    cmp al, ';'
    je .param_done
    inc r12
    dec r14
    jmp .find_semicolon2

.quoted_value:
    inc r12
    dec r14
.find_quote:
    test r14, r14
    jz .param_done
    mov al, [r12]
    cmp al, '"'
    je .found_quote
    inc r12
    dec r14
    jmp .find_quote

.found_quote:
    ; Quoted value
    mov rdi, [rsp + 48]
    mov rsi, r13
    mov rdx, r14
    sub rdx, rsi
    call str_dup_arena
    test rax, rax
    jz .oom
    ; TODO: Store param value

    inc r12
    dec r14
    jmp .param_done

.param_done:
    ; TODO: Store param
    jmp .parse_params

.done_params:
    xor rax, rax
    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.fail:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; mime_match
;   Check if two MIME types match (with wildcards)
;   IN:  rdi = mime1*, rsi = mime2*
;   OUT: rax = 1 if match, 0 if not
; ---------------------------------------------------------------------------
global mime_match
mime_match:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Compare type
    mov rdi, [rbx + MimeType.type]
    mov rsi, [r12 + MimeType.type]
    call str_compare
    test rax, rax
    jnz .check_wildcard1

    ; Compare subtype
    mov rdi, [rbx + MimeType.subtype]
    mov rsi, [r12 + MimeType.subtype]
    call str_compare
    test rax, rax
    jnz .check_wildcard2

    ; Full match
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12
    ret

.check_wildcard1:
    ; Check for wildcard type
    mov rdi, [rbx + MimeType.type]
    mov rsi, [r12 + MimeType.type]
    ; Check if either is "*"
    ; TODO: Implement wildcard matching
    jmp .no_match

.check_wildcard2:
    ; Check for wildcard subtype
    jmp .no_match

.no_match:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; mime_to_string
;   Convert MimeType to string
; ---------------------------------------------------------------------------
global mime_to_string
mime_to_string:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; type/subtype
    mov rdi, r12
    mov rsi, [rbx + MimeType.type]
    call str_copy
    test rax, rax
    jnz .fail

    mov byte [r12], '/'
    inc r12
    dec r13

    mov rdi, r12
    mov rsi, [rbx + MimeType.subtype]
    call str_copy

    EPILOGUE_RESTORE rbx, r12, r13
    ret

.fail:
    mov rax, -(ENOBUFS)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
global mime_version
mime_version: dq 0x010000
