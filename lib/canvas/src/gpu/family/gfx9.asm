; ============================================================================
; AMD GFX9 Family — Command Packet Builders (blit/fill/copy)
; PM4 packet types for GFX/COMPUTE/SDMA rings
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

; struct offsets (hoisted above use)
%define PM4_TYPE_3             3
%define PM4_PFP_SYNC_ME        0x26
%define PM4_DMA_DATA           0x41
%define PM4_COPY_DATA          0x40
%define PM4_FILL_MEM          0x1B
%define PM4_FENCE_WRITE       0x4A
%define PM4_NOP                0x10

section .text


; ---------------------------------------------------------------------------
; gfx9_packet3
;   Build a TYPE-3 header: (count-1)<<16 | (op & 0xFF)<<8 | type
;   IN: rdi=out*, rsi=op, rdx=count
; ---------------------------------------------------------------------------
global gfx9_packet3
gfx_parse_packet3:
gfx9_packet3:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, edx
    dec eax
    shl eax, 16
    mov ecx, esi
    and ecx, 0xFF
    shl ecx, 8
    or eax, ecx
    or eax, PM4_TYPE_3
    mov [rdi], eax
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; gfx9_emit_fill
;   IN: rdi=ring*, rsi=dst_dma, rdx=value, rcx=dwords
; ---------------------------------------------------------------------------
global gfx9_emit_fill
gfx9_emit_fill:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    ASSERT_PTR rbx
    sub rsp, 32
    mov rdi, rsp
    mov rsi, PM4_FILL_MEM
    mov rdx, 5
    call gfx9_packet3
    mov eax, 0  ; engine sel: SDMA-ish fill via CP
    mov [rsp + 4], eax
    mov [rsp + 8], r12d
    shr r12, 32
    mov [rsp + 12], r12d
    mov [rsp + 16], r13d
    mov rax, r14
    mov [rsp + 20], eax
    shr rax, 32
    mov [rsp + 24], eax
    mov rdi, rbx
    mov rsi, rsp
    mov rdx, 7
    call gpu_ring_write
    add rsp, 32
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; gfx9_emit_copy
;   IN: rdi=ring*, rsi=dst_dma, rdx=src_dma, rcx=bytes
; ---------------------------------------------------------------------------
global gfx9_emit_copy
gfx9_emit_copy:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    sub rsp, 32
    mov rdi, rsp
    mov rsi, PM4_DMA_DATA
    mov rdx, 6
    call gfx9_packet3
    ; DMA_DATA: engine(0=me), src/dst sel, cp_sync
    mov dword [rsp + 4], 0x00000000
    mov [rsp + 8], r13d
    shr r13, 32
    mov [rsp + 12], r13d
    mov [rsp + 16], r12d
    mov rax, r12
    shr rax, 32
    mov [rsp + 20], eax
    mov eax, r14d
    mov [rsp + 24], eax
    mov rdi, rbx
    mov rsi, rsp
    mov rdx, 7
    call gpu_ring_write
    add rsp, 32
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; gfx9_emit_fence
;   IN: rdi=ring*, rsi=addr_dma, rdx=seq
; ---------------------------------------------------------------------------
global gfx9_emit_fence
gfx9_emit_fence:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    sub rsp, 24
    mov rdi, rsp
    mov rsi, PM4_FENCE_WRITE
    mov rdx, 4
    call gfx9_packet3
    mov dword [rsp + 4], 0x00000002  ; fence 64-bit
    mov [rsp + 8], r12d
    shr r12, 32
    mov [rsp + 12], r12d
    mov [rsp + 16], r13d
    shr r13, 32
    mov [rsp + 20], r13d
    mov rdi, rbx
    mov rsi, rsp
    mov rdx, 6
    call gpu_ring_write
    add rsp, 24
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
global gfx9_version
gfx9_version: dq 0x010000
