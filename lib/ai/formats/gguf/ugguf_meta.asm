%ifndef GUARD_LIB_AI_FORMATS_UGGUF_META_ASM
%define GUARD_LIB_AI_FORMATS_UGGUF_META_ASM
; =============================================================================
; File     : lib/ai/formats/gguf/ugguf_meta.asm
; Project  : Tattva OS — AI Inference Stack
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: GGUF metadata key-value walking. GGUF metadata is a sequence of
;              null-terminated key strings followed by a value type byte and a
;              value of type-dependent size.
; =============================================================================

bits 64

section .rodata
align 16
; Value type IDs per GGUF spec
gguf_val_uint8:   equ 0
gguf_val_int8:    equ 1
gguf_val_float32: equ 2
gguf_val_bool:    equ 3
gguf_val_str:     equ 4
gguf_val_arr:     equ 5
gguf_val_uint16:  equ 6
gguf_val_int16:   equ 7
gguf_val_float64: equ 8

section .text

; -----------------------------------------------------------------------------
; ugguf_meta_next — Advance to next KV pair and return current key/value info
; Input:  rdi = pointer to current KV pair (key string)
; Output: rax = pointer to next KV pair (or 0 if end of metadata)
;         rbx = pointer to key string (null-terminated)
;         rcx = value type byte
;         rdx = pointer to value data
;         rsi = value size in bytes (0 for variable-length)
; Clobbers: rax, rbx, rcx, rdx, rsi, r8
; -----------------------------------------------------------------------------
global ugguf_meta_next
ugguf_meta_next:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    r8

    mov     rbx, rdi                   ; rbx = key pointer

    ; Scan key string for null terminator
    xor     rcx, rcx
.find_key_end:
    cmp     byte [rbx + rcx], 0
    je      .key_found
    inc     rcx
    jmp     .find_key_end

.key_found:
    add     rbx, rcx
    inc     rbx                        ; skip null terminator

    ; Read value type byte
    movzx   rcx, byte [rbx]
    inc     rbx                        ; skip type byte

    ; rdx = pointer to value data
    mov     rdx, rbx

    ; Parse value based on type
    cmp     rcx, gguf_val_str
    je      .is_str
    cmp     rcx, gguf_val_arr
    je      .is_arr
    cmp     rcx, gguf_val_uint8
    je      .is_fixed1
    cmp     rcx, gguf_val_int8
    je      .is_fixed1
    cmp     rcx, gguf_val_float32
    je      .is_fixed4
    cmp     rcx, gguf_val_bool
    je      .is_bool
    cmp     rcx, gguf_val_uint16
    je      .is_fixed2
    cmp     rcx, gguf_val_int16
    je      .is_fixed2
    cmp     rcx, gguf_val_float64
    je      .is_fixed8
    jmp     .is_unknown

.is_bool:
    mov     rsi, 1                     ; size = 1 byte
    add     rbx, 1
    jmp     .done

.is_fixed1:
    mov     rsi, 1
    add     rbx, 1
    jmp     .done

.is_fixed2:
    mov     rsi, 2
    add     rbx, 2
    jmp     .done

.is_fixed4:
    mov     rsi, 4
    add     rbx, 4
    jmp     .done

.is_fixed8:
    mov     rsi, 8
    add     rbx, 8
    jmp     .done

.is_str:
    ; null-terminated string value
    mov     rsi, rbx
.str_scan:
    cmp     byte [rbx], 0
    je      .str_end
    inc     rbx
    jmp     .str_scan
.str_end:
    inc     rbx                        ; skip null
    mov     r8, rbx
    sub     r8, rsi                    ; r8 = string length
    mov     rsi, r8
    jmp     .done

.is_arr:
    ; Array: elem_type (u8), nelem (u64), then elements
    movzx   rcx, byte [rbx]
    inc     rbx
    mov     rsi, [rbx]                 ; nelem count
    add     rbx, 8
    ; Skip elements (conservative: assume 8 bytes each)
    mov     rax, rsi
    shl     rax, 3
    add     rbx, rax
    mov     rsi, 0                     ; variable, caller handles
    jmp     .done

.is_unknown:
    mov     rsi, 0
    add     rbx, 8                     ; conservative skip

.done:
    mov     rax, rbx                   ; rax = next KV pointer
    pop     r8
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; ugguf_meta_find_key — Find a metadata key by name
; Input:  rdi = start of metadata KV section
;         rsi = pointer to key string to find (null-terminated)
; Output: rax = pointer to value data, or 0 if not found
;         rbx = value type byte
;         rcx = value size
; Clobbers: rax, rbx, rcx, rdx, rsi, rdi, r8, r9
; -----------------------------------------------------------------------------
global ugguf_meta_find_key
ugguf_meta_find_key:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9

    mov     r9, rdi                    ; r9 = metadata start pointer (current pos)
    mov     r8, rsi                    ; r8 = search key pointer

.find_loop:
    ; Call ugguf_meta_next to get next KV pair
    mov     rdi, r9
    call    ugguf_meta_next
    test    rax, rax
    jz      .not_found                 ; no more pairs

    ; rbx = current key, rcx = type, rdx = value data
    ; rsi = value size (clobbered by ugguf_meta_next, but we have search key in r8)

    ; Compare key string: rbx (current key) vs r8 (search key)
    mov     rdi, rbx                   ; current key
    mov     rsi, r8                    ; search key
.compare_loop:
    mov     al, [rdi]
    mov     dl, [rsi]
    cmp     al, dl
    jne     .find_loop                 ; key mismatch, try next
    test    al, al
    jz      .key_match                 ; both null-terminated, match
    inc     rdi
    inc     rsi
    jmp     .compare_loop

.key_match:
    mov     rax, rdx                   ; rax = value data pointer
    ; rbx already holds value type from ugguf_meta_next
    jmp .done

.not_found:
    xor     rax, rax
    xor     rbx, rbx
    xor     rcx, rcx

.done:
    pop     r9
    pop     r8
    pop     rsi
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

%endif ; GUARD_LIB_AI_FORMATS_UGGUF_META_ASM