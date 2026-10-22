; ============================================================================
; Adaptive — Bandwidth-Adaptive Encoder Choice (raw/RLE/deflate/delta)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

extern arena_alloc

; struct offsets (hoisted above use)
%define AdaptiveCtx_SIZE    56
%define ENC_RAW       0
%define ENC_RLE       1
%define ENC_DEFLATE   2
%define ENC_DELTA     3

section .text

struc AdaptiveCtx
    .bandwidth_bps:  resq 1
    .rtt_ns:         resq 1
    .loss_permille:  resd 1
    .last_choice:    resd 1
    .bytes_raw:      resq 1
    .bytes_rle:      resq 1
    .bytes_deflate:  resq 1
    .bytes_delta:    resq 1
endstruc


; ---------------------------------------------------------------------------
; adaptive_init
; ---------------------------------------------------------------------------
global adaptive_init
adaptive_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, r12
    mov rsi, AdaptiveCtx_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov qword [rbx + AdaptiveCtx.bandwidth_bps], 100 * 1000 * 1000
    mov qword [rbx + AdaptiveCtx.rtt_ns], 20000000
    mov dword [rbx + AdaptiveCtx.loss_permille], 0
    mov dword [rbx + AdaptiveCtx.last_choice], ENC_RAW
    mov qword [rbx + AdaptiveCtx.bytes_raw], 0
    mov qword [rbx + AdaptiveCtx.bytes_rle], 0
    mov qword [rbx + AdaptiveCtx.bytes_deflate], 0
    mov qword [rbx + AdaptiveCtx.bytes_delta], 0
    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; adaptive_update_stats
; ---------------------------------------------------------------------------
global adaptive_update_stats
adaptive_update_stats:
    PROLOGUE
    ASSERT_PTR rdi
    mov [rdi + AdaptiveCtx.bandwidth_bps], rsi
    mov [rdi + AdaptiveCtx.rtt_ns], rdx
    mov [rdi + AdaptiveCtx.loss_permille], ecx
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; adaptive_choose
;   IN: rdi = ctx, rsi = tile_pixels, rdx = changed_pixels, rcx = flat (1 if solid)
;   OUT: rax = encoder id
; ---------------------------------------------------------------------------
global adaptive_choose
adaptive_choose:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    ; solid tiles -> RLE always wins
    test rcx, rcx
    jz .not_flat
    mov dword [rbx + AdaptiveCtx.last_choice], ENC_RLE
    mov rax, ENC_RLE
    EPILOGUE_RESTORE rbx
    ret
.not_flat:
    ; few changes -> delta
    mov rax, rdx
    shl rax, 4  ; changed*16 < total ?
    cmp rax, rsi
    jb .use_delta
    ; high bandwidth + low rtt -> raw (lowest CPU)
    mov rax, [rbx + AdaptiveCtx.bandwidth_bps]
    cmp rax, 50 * 1000 * 1000
    jb .use_deflate
    mov rax, [rbx + AdaptiveCtx.rtt_ns]
    cmp rax, 50000000
    ja .use_deflate
    mov dword [rbx + AdaptiveCtx.last_choice], ENC_RAW
    mov rax, ENC_RAW
    EPILOGUE_RESTORE rbx
    ret
.use_delta:
    mov dword [rbx + AdaptiveCtx.last_choice], ENC_DELTA
    mov rax, ENC_DELTA
    EPILOGUE_RESTORE rbx
    ret
.use_deflate:
    mov dword [rbx + AdaptiveCtx.last_choice], ENC_DEFLATE
    mov rax, ENC_DEFLATE
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; adaptive_note_bytes
; ---------------------------------------------------------------------------
global adaptive_note_bytes
adaptive_note_bytes:
    PROLOGUE
    ASSERT_PTR rdi
    cmp rsi, 4
    jae .done
    shl rsi, 3
    add [rdi + AdaptiveCtx.bytes_raw], rdx
    add [rdi + rsi + AdaptiveCtx.bytes_raw], rdx
.done:
    xor rax, rax
    leave
    ret

section .data
global adaptive_version
adaptive_version: dq 0x010000
