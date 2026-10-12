; ============================================================================
; Fuzz Driver Skeleton — Coverage-Guided Fuzzing for Parsers
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

; ---------------------------------------------------------------------------
; fuzz_main
;   Main fuzz entry point
;   IN:  rdi = corpus_dir, rsi = output_dir
; ---------------------------------------------------------------------------
global fuzz_main
fuzz_main:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15

    mov rdi, fuzz_banner
    mov rsi, fuzz_banner_len
    call tv_log_write

    ; TODO: Implement
    ; 1. Load seed corpus
    ; 2. Initialize coverage tracking
    ; 3. Mutation loop
    ; 4. Execute target with mutated input
    ; 5. Track new coverage
    ; 6. Save interesting inputs

    xor rax, rax
    call tv_task_exit
    UNREACHABLE

; ---------------------------------------------------------------------------
; fuzz_target_wire
;   Fuzz wire protocol parser
;   IN:  rdi = input_ptr, rsi = input_len
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global fuzz_target_wire
fuzz_target_wire:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Validate message
    mov rdi, rbx
    mov rsi, r12
    call wire_validate_message
    test rax, rax
    jnz .done

    ; Decode header
    sub rsp, 12
    mov rdi, rbx
    mov rsi, rsp
    call wire_decode_header
    test rax, rax
    jnz .done

    ; Try to decode handles
    mov rdi, rbx
    add rdi, 12
    sub rsp, 64
    mov rsi, rsp
    mov rdx, 16
    call wire_decode_handles

.done:
    add rsp, 76
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; fuzz_target_png
;   Fuzz PNG decoder
; ---------------------------------------------------------------------------
global fuzz_target_png
fuzz_target_png:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; TODO: Call PNG decoder with fuzzed input
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; fuzz_target_jpeg
;   Fuzz JPEG decoder
; ---------------------------------------------------------------------------
global fuzz_target_jpeg
fuzz_target_jpeg:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; TODO: Call JPEG decoder with fuzzed input
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; fuzz_target_ttf
;   Fuzz TTF parser
; ---------------------------------------------------------------------------
global fuzz_target_ttf
fuzz_target_ttf:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; TODO: Call TTF parser with fuzzed input
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; fuzz_target_keymap
;   Fuzz keymap parser
; ---------------------------------------------------------------------------
global fuzz_target_keymap
fuzz_target_keymap:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; TODO: Call keymap parser with fuzzed input
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; fuzz_target_config
;   Fuzz config parser
; ---------------------------------------------------------------------------
global fuzz_target_config
fuzz_target_config:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; TODO: Call config parser with fuzzed input
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; fuzz_target_icc
;   Fuzz ICC profile parser
; ---------------------------------------------------------------------------
global fuzz_target_icc
fuzz_target_icc:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; TODO: Call ICC parser with fuzzed input
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; fuzz_target_rfb
;   Fuzz RFB protocol
; ---------------------------------------------------------------------------
global fuzz_target_rfb
fuzz_target_rfb:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; TODO: Call RFB decoder with fuzzed input
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .rodata

fuzz_banner: db "Canvas Fuzz Driver", 10, "==================", 10, 0
fuzz_banner_len: equ $ - fuzz_banner

section .data
global fuzz_version
fuzz_version: dq 0x010000