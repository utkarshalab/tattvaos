%ifndef GUARD_LIB_AI_FORMATS_UGGUF_TENSOR_ASM
%define GUARD_LIB_AI_FORMATS_UGGUF_TENSOR_ASM
; =============================================================================
; File     : lib/ai/formats/gguf/ugguf_tensor.asm
; Project  : Tattva OS — AI Inference Stack
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: GGUF tensor table parsing — iterate tensor info entries,
;              read name, dimensions, dtype, and data offset.
; =============================================================================

bits 64

section .text

; -----------------------------------------------------------------------------
; ugguf_tensor_table_offset — Compute offset of tensor info table
; Input:  rdi = base pointer to GGUF file
;         rsi = metadata_kv_count (u64)
; Output: rax = file offset of tensor info table (from base)
;         rbx = pointer to first tensor entry (rdi + offset)
; Clobbers: rax, rbx, rcx, rdx, rsi
; -----------------------------------------------------------------------------
global ugguf_tensor_table_offset
ugguf_tensor_table_offset:
    push    rbx
    push    rcx
    push    rdx
    push    rsi

    mov     rbx, rdi                   ; rbx = current position in file
    add     rbx, 24                    ; skip GGUF header (24 bytes)
    mov     rcx, rsi                   ; rcx = remaining KV count

.walk_meta:
    test    rcx, rcx
    jz      .walk_done

    ; Skip key string (null-terminated)
.skip_key:
    cmp     byte [rbx], 0
    je      .key_end
    inc     rbx
    jmp     .skip_key
.key_end:
    inc     rbx                        ; skip null terminator

    ; Read value type byte
    movzx   eax, byte [rbx]
    inc     rbx

    ; Skip value based on type
    cmp     eax, 4                     ; GGUF_VAL_STR
    je      .val_str
    cmp     eax, 5                     ; GGUF_VAL_ARR
    je      .val_arr
    cmp     eax, 0                     ; UINT8
    je      .val_1
    cmp     eax, 1                     ; INT8
    je      .val_1
    cmp     eax, 2                     ; FLOAT32
    je      .val_4
    cmp     eax, 3                     ; BOOL
    je      .val_1
    cmp     eax, 6                     ; UINT16
    je      .val_2
    cmp     eax, 7                     ; INT16
    je      .val_2
    cmp     eax, 8                     ; UINT64
    je      .val_8
    cmp     eax, 9                     ; INT64
    je      .val_8
    cmp     eax, 10                    ; FLOAT64
    je      .val_8
    jmp     .val_8                     ; default: skip 8 bytes

.val_str:
    mov     rsi, rbx
.str_scan:
    cmp     byte [rbx], 0
    je      .str_end
    inc     rbx
    jmp     .str_scan
.str_end:
    inc     rbx                        ; skip null
    jmp     .kv_done

.val_arr:
    movzx   eax, byte [rbx]            ; elem_type
    inc     rbx
    mov     rax, [rbx]                 ; nelem (u64)
    add     rbx, 8
    shl     rax, 3                     ; assume 8 bytes per element
    add     rbx, rax
    jmp     .kv_done

.val_1:
    add     rbx, 1
    jmp     .kv_done
.val_2:
    add     rbx, 2
    jmp     .kv_done
.val_4:
    add     rbx, 4
    jmp     .kv_done
.val_8:
    add     rbx, 8
    jmp     .kv_done

.kv_done:
    dec     rcx
    jmp     .walk_meta

.walk_done:
    sub     rbx, rdi                   ; rax = offset from base
    mov     rax, rbx
    mov     rbx, rdi
    add     rbx, rax                   ; rbx = pointer to first tensor entry
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; ugguf_tensor_count — Return tensor count from GGUF header
; Input:  rdi = base pointer to GGUF file
; Output: rax = tensor count (u64)
; -----------------------------------------------------------------------------
global ugguf_tensor_count
ugguf_tensor_count:
    mov     rax, [rdi + 8]
    ret

; -----------------------------------------------------------------------------
; ugguf_tensor_info_at — Parse a single tensor info entry at given index
; Input:  rdi = pointer to tensor info array start
;         rsi = tensor index (0-based)
; Output: rax = 0 on success, non-zero on error
;         rbx = pointer to tensor name string (null-terminated)
;         rcx = ndims (u32)
;         rdx = pointer to dims array (u64[ndims])
;         r8  = dtype (u32)
;         r9  = data offset (u64, file offset to tensor payload)
; Clobbers: rax, rbx, rcx, rdx, r8, r9
; -----------------------------------------------------------------------------
global ugguf_tensor_info_at
ugguf_tensor_info_at:
    push    rbx
    push    rcx
    push    rdx
    push    r8
    push    r9

    mov     rbx, rdi                   ; rbx = tensor array base
    mov     rcx, rsi                   ; rcx = target index
    xor     r8, r8                     ; r8 = current index
    mov     r9, rdi                    ; r9 = current tensor entry pointer

.walk_tensors:
    cmp     r8, rcx
    je      .tensor_found

    ; Parse current tensor entry to advance to next
    mov     rdi, r9
.name_scan:
    cmp     byte [rdi], 0
    je      .name_end
    inc     rdi
    jmp     .name_scan
.name_end:
    inc     rdi                        ; skip null terminator

    ; Read ndims (u32)
    movzx   ecx, dword [rdi]
    add     rdi, 4

    ; Skip dims (ndims * 8 bytes)
    mov     rsi, rcx
    shl     rsi, 3
    add     rdi, rsi

    ; Skip dtype (u32)
    add     rdi, 4

    ; Skip offset (u64)
    add     rdi, 8

    inc     r8
    mov     r9, rdi
    jmp     .walk_tensors

.tensor_found:
    mov     rdi, r9                    ; rdi = this tensor entry start

    ; rbx = pointer to tensor name
    mov     rbx, rdi

    ; Scan past name to ndims
.name_scan2:
    cmp     byte [rdi], 0
    je      .name_end2
    inc     rdi
    jmp     .name_scan2
.name_end2:
    inc     rdi                        ; skip null terminator

    ; Read ndims (u32)
    movzx   ecx, dword [rdi]
    add     rdi, 4

    ; rdx = pointer to dims array
    mov     rdx, rdi
    add     rdi, rcx
    shl     rcx, 3                     ; rcx = ndims * 8 for skip
    add     rdi, rcx                   ; skip dims

    ; r8 = dtype
    movzx   r8d, dword [rdi]
    add     rdi, 4

    ; r9 = data offset
    mov     r9, [rdi]

    xor     rax, rax                   ; success
    jmp     .done

.err:
    mov     rax, 1

.done:
    pop     r9
    pop     r8
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; ugguf_tensor_ptr — Compute direct pointer to tensor data
; Input:  rdi = base pointer to GGUF file
;         rsi = data offset (u64, from ugguf_tensor_info_at)
; Output: rax = pointer into file at tensor data
; -----------------------------------------------------------------------------
global ugguf_tensor_ptr
ugguf_tensor_ptr:
    add     rax, rdi
    ret

%endif ; GUARD_LIB_AI_FORMATS_UGGUF_TENSOR_ASM