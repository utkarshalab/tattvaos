%ifndef GUARD_LIB_STR_PARSE_JSON_ASM
%define GUARD_LIB_STR_PARSE_JSON_ASM
; =============================================================================
; str/parse/json.asm
; Zero-copy streaming JSON parser callback engine.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

JSON_NULL       equ 1
JSON_BOOL       equ 2
JSON_NUMBER     equ 3
JSON_STRING     equ 4
JSON_ARRAY      equ 5
JSON_OBJECT     equ 6

section .text

; -----------------------------------------------------------------------------
; str_json_parse
;
; Streaming JSON object parser that calls a callback for each key-value pair.
;
; Signature:
;   int64_t str_json_parse(const StrSlice *json,
;                          int64_t (*callback)(const StrSlice *key,
;                                              const StrSlice *val,
;                                              uint8_t type, void *ctx),
;                          void *ctx)
; -----------------------------------------------------------------------------
STR_FUNC str_json_parse
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 64             ; local slices: [rsp] = key, [rsp + 16] = val

    mov     rbx, [rdi + StrSlice.ptr]   ; cursor
    mov     r12, rbx
    add     r12, [rdi + StrSlice.len]   ; end
    mov     r13, rsi                    ; callback
    mov     r14, rdx                    ; ctx

.skip_ws_start:
    cmp     rbx, r12
    jae     .parse_err
    movzx   eax, byte [rbx]
    cmp     al, ' '
    je      .next_ws_start
    cmp     al, 0x09
    je      .next_ws_start
    cmp     al, 0x0A
    je      .next_ws_start
    cmp     al, 0x0D
    je      .next_ws_start
    jmp     .check_obj_start

.next_ws_start:
    inc     rbx
    jmp     .skip_ws_start

.check_obj_start:
    cmp     byte [rbx], '{'
    jne     .parse_err          ; must start with object
    inc     rbx                 ; past '{'

.member_loop:
    call    .skip_ws
    cmp     rbx, r12
    jae     .parse_err

    cmp     byte [rbx], '}'
    je      .obj_done

    ; must be string key starting with '"'
    cmp     byte [rbx], '"'
    jne     .parse_err
    inc     rbx                 ; past '"'

    mov     [rsp + StrSlice.ptr], rbx   ; key start
.key_loop:
    cmp     rbx, r12
    jae     .parse_err
    cmp     byte [rbx], '"'
    je      .key_end
    inc     rbx
    jmp     .key_loop

.key_end:
    mov     rax, rbx
    sub     rax, [rsp + StrSlice.ptr]
    mov     [rsp + StrSlice.len], rax
    inc     rbx                 ; past '"'

    ; skip whitespace, find ':'
    call    .skip_ws
    cmp     rbx, r12
    jae     .parse_err
    cmp     byte [rbx], ':'
    jne     .parse_err
    inc     rbx                 ; past ':'

    call    .skip_ws
    cmp     rbx, r12
    jae     .parse_err

    ; parse value
    movzx   eax, byte [rbx]
    cmp     al, '"'
    je      .val_string
    cmp     al, 't'
    je      .val_true
    cmp     al, 'f'
    je      .val_false
    cmp     al, 'n'
    je      .val_null
    cmp     al, '['
    je      .val_array
    cmp     al, '{'
    je      .val_object

    ; else check if number
    cmp     al, '-'
    je      .val_num
    cmp     al, '0'
    jb      .parse_err
    cmp     al, '9'
    jbe     .val_num

    jmp     .parse_err

.val_string:
    inc     rbx
    mov     [rsp + 16 + StrSlice.ptr], rbx
.val_str_loop:
    cmp     rbx, r12
    jae     .parse_err
    cmp     byte [rbx], '"'
    je      .val_str_end
    inc     rbx
    jmp     .val_str_loop
.val_str_end:
    mov     rax, rbx
    sub     rax, [rsp + 16 + StrSlice.ptr]
    mov     [rsp + 16 + StrSlice.len], rax
    inc     rbx                 ; past '"'
    mov     r15b, JSON_STRING
    jmp     .dispatch_callback

.val_true:
    ; must be "true"
    mov     rax, r12
    sub     rax, rbx
    cmp     rax, 4
    jb      .parse_err
    ; verify "true"
    cmp     byte [rbx + 1], 'r'
    jne     .parse_err
    cmp     byte [rbx + 2], 'u'
    jne     .parse_err
    cmp     byte [rbx + 3], 'e'
    jne     .parse_err
    mov     [rsp + 16 + StrSlice.ptr], rbx
    mov     qword [rsp + 16 + StrSlice.len], 4
    add     rbx, 4
    mov     r15b, JSON_BOOL
    jmp     .dispatch_callback

.val_false:
    ; must be "false"
    mov     rax, r12
    sub     rax, rbx
    cmp     rax, 5
    jb      .parse_err
    cmp     byte [rbx + 1], 'a'
    jne     .parse_err
    cmp     byte [rbx + 2], 'l'
    jne     .parse_err
    cmp     byte [rbx + 3], 's'
    jne     .parse_err
    cmp     byte [rbx + 4], 'e'
    jne     .parse_err
    mov     [rsp + 16 + StrSlice.ptr], rbx
    mov     qword [rsp + 16 + StrSlice.len], 5
    add     rbx, 5
    mov     r15b, JSON_BOOL
    jmp     .dispatch_callback

.val_null:
    mov     rax, r12
    sub     rax, rbx
    cmp     rax, 4
    jb      .parse_err
    cmp     byte [rbx + 1], 'u'
    jne     .parse_err
    cmp     byte [rbx + 2], 'l'
    jne     .parse_err
    cmp     byte [rbx + 3], 'l'
    jne     .parse_err
    mov     [rsp + 16 + StrSlice.ptr], rbx
    mov     qword [rsp + 16 + StrSlice.len], 4
    add     rbx, 4
    mov     r15b, JSON_NULL
    jmp     .dispatch_callback

.val_array:
    ; scan until matching ']'
    mov     [rsp + 16 + StrSlice.ptr], rbx
    xor     ecx, ecx            ; brackets balance
.arr_loop:
    cmp     rbx, r12
    jae     .parse_err
    movzx   eax, byte [rbx]
    cmp     al, '['
    jne     .arr_check_close
    inc     ecx
    jmp     .arr_next
.arr_check_close:
    cmp     al, ']'
    jne     .arr_next
    dec     ecx
    jz      .arr_end
.arr_next:
    inc     rbx
    jmp     .arr_loop
.arr_end:
    inc     rbx                 ; past ']'
    mov     rax, rbx
    sub     rax, [rsp + 16 + StrSlice.ptr]
    mov     [rsp + 16 + StrSlice.len], rax
    mov     r15b, JSON_ARRAY
    jmp     .dispatch_callback

.val_object:
    ; scan until matching '}'
    mov     [rsp + 16 + StrSlice.ptr], rbx
    xor     ecx, ecx
.obj_scan_loop:
    cmp     rbx, r12
    jae     .parse_err
    movzx   eax, byte [rbx]
    cmp     al, '{'
    jne     .obj_check_close
    inc     ecx
    jmp     .obj_scan_next
.obj_check_close:
    cmp     al, '}'
    jne     .obj_scan_next
    dec     ecx
    jz      .obj_scan_end
.obj_scan_next:
    inc     rbx
    jmp     .obj_scan_loop
.obj_scan_end:
    inc     rbx
    mov     rax, rbx
    sub     rax, [rsp + 16 + StrSlice.ptr]
    mov     [rsp + 16 + StrSlice.len], rax
    mov     r15b, JSON_OBJECT
    jmp     .dispatch_callback

.val_num:
    mov     [rsp + 16 + StrSlice.ptr], rbx
.num_loop:
    cmp     rbx, r12
    jae     .num_end
    movzx   eax, byte [rbx]
    cmp     al, '-'
    je      .num_next
    cmp     al, '.'
    je      .num_next
    cmp     al, 'e'
    je      .num_next
    cmp     al, 'E'
    je      .num_next
    cmp     al, '0'
    jb      .num_end
    cmp     al, '9'
    ja      .num_end
.num_next:
    inc     rbx
    jmp     .num_loop
.num_end:
    mov     rax, rbx
    sub     rax, [rsp + 16 + StrSlice.ptr]
    mov     [rsp + 16 + StrSlice.len], rax
    mov     r15b, JSON_NUMBER

.dispatch_callback:
    ; call callback(key, val, type, ctx)
    lea     rdi, [rsp]
    lea     rsi, [rsp + 16]
    movzx   edx, r15b
    mov     rcx, r14
    call    r13
    test    rax, rax
    jnz     .cb_aborted         ; non-zero aborts parsing

    call    .skip_ws
    cmp     rbx, r12
    jae     .parse_err

    movzx   eax, byte [rbx]
    cmp     al, ','
    je      .next_member
    cmp     al, '}'
    je      .obj_done
    jmp     .parse_err

.next_member:
    inc     rbx
    jmp     .member_loop

.obj_done:
    inc     rbx                 ; past '}'
    xor     eax, eax
    add     rsp, 64
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.cb_aborted:
    mov     rax, STR_ERR_INVALID
    add     rsp, 64
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.parse_err:
    mov     rax, STR_ERR_INVALID
    add     rsp, 64
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

; Helper to skip whitespace
.skip_ws:
    cmp     rbx, r12
    jae     .skip_ws_ret
    movzx   eax, byte [rbx]
    cmp     al, ' '
    je      .skip_ws_next
    cmp     al, 0x09
    je      .skip_ws_next
    cmp     al, 0x0A
    je      .skip_ws_next
    cmp     al, 0x0D
    je      .skip_ws_next
    ret
.skip_ws_next:
    inc     rbx
    jmp     .skip_ws
.skip_ws_ret:
    ret
STR_ENDFUNC str_json_parse

%endif ; GUARD_LIB_STR_PARSE_JSON_ASM
