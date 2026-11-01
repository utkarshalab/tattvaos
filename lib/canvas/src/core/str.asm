; ============================================================================
; String Operations — str_cmp, str_len, str_dup_arena
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern memcopy

section .text

; ---------------------------------------------------------------------------
; str_len
;   Get string length
;   IN:  rdi = string pointer
;   OUT: rax = length (not including null terminator)
; ---------------------------------------------------------------------------
global str_len
str_len:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    xor rax, rax
.loop:
    cmp byte [rbx + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; str_cmp
;   Compare strings (lexicographic)
;   IN:  rdi = string1, rsi = string2
;   OUT: rax = 0 if equal, negative/positive if different
; ---------------------------------------------------------------------------
global str_cmp
str_cmp:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
.loop:
    mov al, [rbx]
    mov dl, [r12]
    cmp al, dl
    jne .diff
    test al, al
    jz .equal
    inc rbx
    inc r12
    jmp .loop
.diff:
    sbb rax, rax
    or rax, 1
    EPILOGUE_RESTORE rbx, r12
    ret
.equal:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; str_ncmp
;   Compare strings up to n characters
;   IN:  rdi = string1, rsi = string2, rdx = max count
;   OUT: rax = 0 if equal, negative/positive if different
; ---------------------------------------------------------------------------
global str_ncmp
str_ncmp:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    test r13, r13
    jz .equal
.loop:
    mov al, [rbx]
    mov dl, [r12]
    cmp al, dl
    jne .diff
    test al, al
    jz .equal
    inc rbx
    inc r12
    dec r13
    jnz .loop
.equal:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.diff:
    sbb rax, rax
    or rax, 1
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; str_dup_arena
;   Duplicate string using arena allocator
;   IN:  rdi = arena*, rsi = string
;   OUT: rax = new string pointer, 0 on error
; ---------------------------------------------------------------------------
global str_dup_arena
str_dup_arena:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    
    ; Get string length
    mov rdi, r12
    call str_len
    test rax, rax
    jz .empty
    mov r13, rax
    inc r13
    
    ; Allocate
    mov rdi, rbx
    mov rsi, r13
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax                ; the copy (r13 keeps the size)

    ; Copy string, with its terminator
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call memcopy

    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12, r13
    ret
    
.empty:
    mov rdi, rbx
    mov rsi, 1
    call arena_alloc
    test rax, rax
    jz .oom
    mov byte [rax], 0
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; str_cat_arena
;   Concatenate strings using arena
;   IN:  rdi = arena*, rsi = string1, rdx = string2
;   OUT: rax = concatenated string, 0 on error
; ---------------------------------------------------------------------------
global str_cat_arena
str_cat_arena:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Get lengths
    mov rdi, r12
    call str_len
    mov r14, rax                ; first

    mov rdi, r13
    call str_len
    mov r15, rax                ; second

    ; Allocate both and the terminator
    mov rdi, rbx
    lea rsi, [r14 + r15 + 1]
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Copy first string
    mov rdi, rax
    mov rsi, r12
    mov rdx, r14
    call memcopy

    ; Copy second string, with its terminator
    lea rdi, [rbx + r14]
    mov rsi, r13
    lea rdx, [r15 + 1]
    call memcopy

    mov rax, rbx
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.oom:
    xor rax, rax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; str_find_char
;   Find character in string
;   IN:  rdi = string, rsi = char
;   OUT: rax = pointer to char, 0 if not found
; ---------------------------------------------------------------------------
global str_find_char
str_find_char:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
.loop:
    mov al, [rbx]
    cmp al, sil
    je .found
    test al, al
    jz .not_found
    inc rbx
    jmp .loop
.found:
    mov rax, rbx
    EPILOGUE_RESTORE rbx            ; rbx is the caller's
    ret
.not_found:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; str_find_substr
;   Find substring in string
;   IN:  rdi = haystack, rsi = needle
;   OUT: rax = pointer to match, 0 if not found
; ---------------------------------------------------------------------------
global str_find_substr
str_find_substr:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    
    mov rdi, r12
    call str_len
    mov r13, rax
    test r13, r13
    jz .found_start
    
.find_start:
    mov al, [rbx]
    test al, al
    jz .not_found
    cmp al, [r12]
    jne .next_char
    
    ; Potential match
    push rbx
    push r12
    push r13
    mov r14, rbx
.match_loop:
    mov al, [r14]
    mov dl, [r12]
    cmp al, dl
    jne .no_match
    test al, al
    jz .found_match
    inc r14
    inc r12
    dec r13
    jnz .match_loop
    jmp .found_match
.no_match:
    pop r13
    pop r12
    pop rbx
    jmp .next_char
.found_match:
    add rsp, 24
    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.found_start:
    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.next_char:
    inc rbx
    jmp .find_start
.not_found:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .data
global str_version
str_version: dq 0x010000
