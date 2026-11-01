; ============================================================================
; AMD GFX9 Family — Command Packet Builders (blit/fill/copy)
; PM4 type-3 packets for the GFX / compute command processor
; ============================================================================
; A type-3 header is  3 << 30 | (payload dwords - 1) << 16 | opcode << 8;
; bit 1 (shader type) and bit 0 (predicate) stay clear. Fill and copy are
; DMA_DATA packets (the fill with the source being the data dword), split
; at DMA_MAX_BYTES; the fence is a RELEASE_MEM that writes the 64-bit
; sequence at end of pipe after flushing the caches.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

extern gpu_ring_write

%define PM4_TYPE3_HDR       (3 << 30)
%define PM4_COUNT_MASK      0x3FFF

%define PKT3_NOP            0x10
%define PKT3_WRITE_DATA     0x37
%define PKT3_COPY_DATA      0x40
%define PKT3_PFP_SYNC_ME    0x42
%define PKT3_RELEASE_MEM    0x49
%define PKT3_DMA_DATA       0x50

; DMA_DATA dword 1
%define DMA_CP_SYNC         (1 << 31)       ; finish before the next packet
%define DMA_SRC_ADDR        (0 << 29)
%define DMA_SRC_DATA        (2 << 29)       ; the source dword is the data
%define DMA_DST_ADDR        (0 << 20)
%define DMA_MAX_BYTES       (1 << 21)       ; per packet (BYTE_COUNT has 26 bits)

; RELEASE_MEM dwords 1 and 2
%define EV_CACHE_FLUSH_AND_INV_TS   0x14
%define EV_INDEX_EOP                (5 << 8)
%define RM_DST_MEM                  (0 << 16)
%define RM_DATA_SEL_64              (2 << 29)

section .text

; ---------------------------------------------------------------------------
; gfx9_packet3
;   Write a type-3 header
;   IN: rdi = out*, rsi = opcode, rdx = payload dwords (1 .. 16384)
;   OUT: rax = the header
; ---------------------------------------------------------------------------
global gfx9_packet3
gfx9_packet3:
    lea eax, [rdx - 1]
    and eax, PM4_COUNT_MASK
    shl eax, 16
    movzx ecx, sil
    shl ecx, 8
    or eax, ecx
    or eax, PM4_TYPE3_HDR
    mov [rdi], eax
    ret

; ---------------------------------------------------------------------------
; gfx9_emit_fill
;   IN: rdi=ring*, rsi=dst_dma, rdx=value, rcx=dwords
;   OUT: rax = 0 or the ring's error
; ---------------------------------------------------------------------------
global gfx9_emit_fill
gfx9_emit_fill:
    PROLOGUE_SAVE rbx, r12, r13, r14
    sub rsp, 32
    mov rbx, rdi
    mov r12, rsi                        ; destination
    mov r13d, edx                       ; the value
    lea r14, [rcx * 4]                  ; bytes left
    ASSERT_PTR rbx
    xor eax, eax
.next:
    test r14, r14
    jz .out
    mov rdi, rsp
    mov esi, PKT3_DMA_DATA
    mov edx, 6
    call gfx9_packet3
    mov dword [rsp + 4], DMA_CP_SYNC | DMA_SRC_DATA | DMA_DST_ADDR
    mov [rsp + 8], r13d
    mov dword [rsp + 12], 0
    mov [rsp + 16], r12d
    mov rax, r12
    shr rax, 32
    mov [rsp + 20], eax
    mov eax, DMA_MAX_BYTES
    cmp r14, rax
    cmovb eax, r14d
    mov [rsp + 24], eax                 ; BYTE_COUNT
    add r12, rax
    sub r14, rax
    mov rdi, rbx
    mov rsi, rsp
    mov edx, 7
    call gpu_ring_write
    test rax, rax
    jz .next
.out:
    add rsp, 32
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; gfx9_emit_copy
;   IN: rdi=ring*, rsi=dst_dma, rdx=src_dma, rcx=bytes
;   OUT: rax = 0 or the ring's error
; ---------------------------------------------------------------------------
global gfx9_emit_copy
gfx9_emit_copy:
    PROLOGUE_SAVE rbx, r12, r13, r14
    sub rsp, 32
    mov rbx, rdi
    mov r12, rsi                        ; destination
    mov r13, rdx                        ; source
    mov r14, rcx                        ; bytes left
    ASSERT_PTR rbx
    xor eax, eax
.next:
    test r14, r14
    jz .out
    mov rdi, rsp
    mov esi, PKT3_DMA_DATA
    mov edx, 6
    call gfx9_packet3
    mov dword [rsp + 4], DMA_CP_SYNC | DMA_SRC_ADDR | DMA_DST_ADDR
    mov [rsp + 8], r13d
    mov rax, r13
    shr rax, 32
    mov [rsp + 12], eax
    mov [rsp + 16], r12d
    mov rax, r12
    shr rax, 32
    mov [rsp + 20], eax
    mov eax, DMA_MAX_BYTES
    cmp r14, rax
    cmovb eax, r14d
    mov [rsp + 24], eax                 ; BYTE_COUNT
    add r12, rax
    add r13, rax
    sub r14, rax
    mov rdi, rbx
    mov rsi, rsp
    mov edx, 7
    call gpu_ring_write
    test rax, rax
    jz .next
.out:
    add rsp, 32
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; gfx9_emit_fence
;   IN: rdi=ring*, rsi=addr_dma (8-byte aligned), rdx=seq
;   OUT: rax = 0, -EINVAL for an unaligned address, or the ring's error
; ---------------------------------------------------------------------------
global gfx9_emit_fence
gfx9_emit_fence:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 40                         ; the packet; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    mov rax, -(EINVAL)
    test r12, 7
    jnz .out
    mov rdi, rsp
    mov esi, PKT3_RELEASE_MEM
    mov edx, 7
    call gfx9_packet3
    mov dword [rsp + 4], EV_CACHE_FLUSH_AND_INV_TS | EV_INDEX_EOP
    mov dword [rsp + 8], RM_DATA_SEL_64 | RM_DST_MEM
    mov [rsp + 12], r12d
    shr r12, 32
    mov [rsp + 16], r12d
    mov [rsp + 20], r13d
    shr r13, 32
    mov [rsp + 24], r13d
    mov dword [rsp + 28], 0             ; INT_CTXID
    mov rdi, rbx
    mov rsi, rsp
    mov edx, 8
    call gpu_ring_write
.out:
    add rsp, 40
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
global gfx9_version
gfx9_version: dq 0x010100
