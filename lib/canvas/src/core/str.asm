; ============================================================================
; String Library — Zero-Terminated Strings, Arena-Aware
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

; ---------------------------------------------------------------------------
; str_len
;   Get string length (not including null terminator)
;   IN:  rdi = string pointer
;   OUT: rax = length
; ---------------------------------------------------------------------------
global str_len
str_len:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    xor rax, rax
.loop:
    cmp byte [rbx + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    EPILOGUE_RESTORE rbx

; ---------------------------------------------------------------------------
; str_copy
;   Copy string to destination buffer
;   IN:  rdi = dst, rsi = src, rdx = dst_size
;   OUT: rax = bytes copied (excl null), negative error if truncated
; ---------------------------------------------------------------------------
global str_copy
str_copy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi        ; dst
    mov r12, rsi        ; src
    ASSERT_PTR rbx
    ASSERT_PTR r12
    test rdx, rdx
    jz .done
    dec rdx             ; reserve space for null
    xor rax, rax
.loop:
    cmp rax, rdx
    jae .truncated
    mov cl, [r12 + rax]
    mov [rbx + rax], cl
    test cl, cl
    jz .done
    inc rax
    jmp .loop
.truncated:
    mov byte [rbx + rdx], 0
    mov rax, -ENOBUFS
    EPILOGUE_RESTORE rbx, r12
    ret
.done:
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; str_ncopy
;   Copy at most n chars from src to dst
;   IN:  rdi = dst, rsi = src, rdx = max_chars
;   OUT: rax = chars copied
; ---------------------------------------------------------------------------
global str_ncopy
str_ncopy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    xor rax, rax
    test rdx, rdx
    jz .done
.loop:
    cmp rax, rdx
    jae .done
    mov cl, [r12 + rax]
    mov [rbx + rax], cl
    test cl, cl
    jz .done
    inc rax
    jmp .loop
.done:
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; str_compare
;   Compare two strings (strcmp)
;   IN:  rdi = s1, rsi = s2
;   OUT: rax = 0 equal, <0 s1<s2, >0 s1>s2
; ---------------------------------------------------------------------------
global str_compare
str_compare:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
.loop:
    mov al, [rbx]
    mov cl, [r12]
    cmp al, cl
    jne .diff
    test al, al
    jz .equal
    inc rbx
    inc r12
    jmp .loop
.diff:
    sub al, cl
    movsx rax, al
    EPILOGUE_RESTORE rbx, r12
    ret
.equal:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; str_ncompare
;   Compare at most n chars (strncmp)
;   IN:  rdi = s1, rsi = s2, rdx = n
;   OUT: rax = 0 equal, <0 s1<s2, >0 s1>s2
; ---------------------------------------------------------------------------
global str_ncompare
str_ncompare:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    test r13, r13
    jz .equal
.loop:
    dec r13
    js .equal
    mov al, [rbx]
    mov cl, [r12]
    cmp al, cl
    jne .diff
    test al, al
    jz .equal
    inc rbx
    inc r12
    jmp .loop
.diff:
    sub al, cl
    movsx rax, al
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.equal:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; str_find_char
;   Find first occurrence of char in string (strchr)
;   IN:  rdi = string, rsi = char (byte)
;   OUT: rax = pointer to char, 0 if not found
; ---------------------------------------------------------------------------
global str_find_char
str_find_char:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    movzx rsi, sil
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
    EPILOGUE_RESTORE rbx
    ret
.not_found:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; str_find_last_char
;   Find last occurrence of char (strrchr)
;   IN:  rdi = string, rsi = char
;   OUT: rax = pointer to char, 0 if not found
; ---------------------------------------------------------------------------
global str_find_last_char
str_find_last_char:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, 0
    ASSERT_PTR rbx
    movzx rsi, sil
.loop:
    mov al, [rbx]
    test al, al
    jz .done
    cmp al, sil
    jne .next
    mov r12, rbx
.next:
    inc rbx
    jmp .loop
.done:
    mov rax, r12
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; str_starts_with
;   Check if string starts with prefix
;   IN:  rdi = string, rsi = prefix
;   OUT: rax = 1 if yes, 0 if no
; ---------------------------------------------------------------------------
global str_starts_with
str_starts_with:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
.loop:
    mov al, [r12]
    test al, al
    jz .yes
    cmp al, [rbx]
    jne .no
    inc rbx
    inc r12
    jmp .loop
.yes:
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12
    ret
.no:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; str_ends_with
;   Check if string ends with suffix
;   IN:  rdi = string, rsi = suffix
;   OUT: rax = 1 if yes, 0 if no
; ---------------------------------------------------------------------------
global str_ends_with
str_ends_with:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    call str_len
    mov r13, rax          ; string len
    mov rdi, r12
    call str_len
    ; rax = suffix len
    cmp rax, r13
    ja .no
    sub r13, rax
    add rbx, r13          ; point to potential suffix start
.loop:
    mov al, [r12]
    test al, al
    jz .yes
    cmp al, [rbx]
    jne .no
    inc r12
    inc rbx
    jmp .loop
.yes:
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.no:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; str_to_lower
;   Convert string to lowercase in-place (ASCII only)
;   IN:  rdi = string
;   OUT: rax = string pointer
; ---------------------------------------------------------------------------
global str_to_lower
str_to_lower:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
.loop:
    mov al, [rbx]
    test al, al
    jz .done
    cmp al, 'A'
    jb .next
    cmp al, 'Z'
    ja .next
    add al, 32
    mov [rbx], al
.next:
    inc rbx
    jmp .loop
.done:
    mov rax, rdi
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; str_to_upper
;   Convert string to uppercase in-place (ASCII only)
;   IN:  rdi = string
;   OUT: rax = string pointer
; ---------------------------------------------------------------------------
global str_to_upper
str_to_upper:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
.loop:
    mov al, [rbx]
    test al, al
    jz .done
    cmp al, 'a'
    jb .next
    cmp al, 'z'
    ja .next
    sub al, 32
    mov [rbx], al
.next:
    inc rbx
    jmp .loop
.done:
    mov rax, rdi
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; Arena-Aware String Functions
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; str_dup_arena
;   Duplicate string using arena allocator
;   IN:  rdi = arena, rsi = string
;   OUT: rax = new string pointer, 0 on OOM
; ---------------------------------------------------------------------------
global str_dup_arena
str_dup_arena:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi        ; arena
    mov r12, rsi        ; string
    ASSERT_PTR rbx
    ASSERT_PTR r12
    push r12
    mov rdi, r12
    call str_len
    inc rax             ; +1 for null
    mov rsi, rax
    pop rdi
    call arena_alloc
    test rax, rax
    jz .oom
    mov rdi, rax
    mov rsi, r12
    call str_copy
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; str_concat_arena
;   Concatenate two strings using arena
;   IN:  rdi = arena, rsi = s1, rdx = s2
;   OUT: rax = new string, 0 on OOM
; ---------------------------------------------------------------------------
global str_concat_arena
str_concat_arena:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi        ; arena
    mov r12, rsi        ; s1
    mov r13, rdx        ; s2
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    push r12
    mov rdi, r12
    call str_len
    mov r12, rax
    pop rdi
    push r13
    mov rdi, r13
    call str_len
    mov r13, rax
    pop rdi
    lea rsi, [r12 + r13 + 1]
    call arena_alloc
    test rax, rax
    jz .oom
    push rax
    mov rdi, rax
    mov rsi, r12
    call str_copy
    pop rdi
    add rdi, r12
    mov rsi, r13
    call str_copy
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data

global str_version
str_version: dq 0x010000
