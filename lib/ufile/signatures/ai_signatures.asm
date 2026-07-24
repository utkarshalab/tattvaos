; =============================================================================
; Tattva OS — lib/ufile/signatures/ai_signatures.asm
; =============================================================================
; AI / ML Model Signature Matchers (GGUF, Safetensors, ONNX).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "ufile.inc"

section .text

; -----------------------------------------------------------------------------
; match_gguf — Match and extract GGUF AI model metadata
; Input:  RDI = Buffer pointer, RSI = Output ufile_meta_t pointer
; Output: RAX = 1 if matched, 0 if not
; -----------------------------------------------------------------------------
match_gguf:
    ; GGUF magic 0x46554747 "GGUF" at offset 0
    mov eax, [rdi]
    cmp eax, 0x46554747             ; "GGUF" in little-endian
    jne .no_match

    mov dword [rsi + ufile_meta_t.type_id], UFILE_TYPE_GGUF
    mov dword [rsi + ufile_meta_t.category], UFILE_CAT_AI_MODEL
    mov qword [rsi + ufile_meta_t.mime_str], str_mime_gguf
    mov qword [rsi + ufile_meta_t.ext_str], str_ext_gguf

    ; Extract GGUF Version at offset 4
    mov eax, [rdi + 4]
    mov [rsi + ufile_meta_t.version], eax

    ; Extract Tensor Count at offset 8 (64-bit uint)
    mov rax, [rdi + 8]
    mov [rsi + ufile_meta_t.param1], rax

    ; Extract Key-Value Count at offset 16 (64-bit uint)
    mov rax, [rdi + 16]
    mov [rsi + ufile_meta_t.param2], rax

    mov rax, 1
    ret

.no_match:
    xor rax, rax
    ret

section .data
str_mime_gguf: db 'application/x-gguf', 0
str_ext_gguf:  db '.gguf', 0
