; =============================================================================
; Tattva OS — storage/ubxp/ubxp.asm
; =============================================================================
; Master UBXP (Unikernel Binary eXchange Protocol) Subsystem Dispatcher.
;
; Single-pass NASM included subsystem handler linking every UBXP sub-module:
;   - Frame layer:  header emission, validation, CRC32C, LEB128 varints
;   - Type layer:   scalars, zig-zag integers, length-delimited blobs
;   - Schema layer: field tags, unknown-field skipping, version negotiation
;
; UBXP is the serialization format shared by udb's storage records, uobject's
; metadata and the urpc wire protocol. It is unrelated to the boot-time BXP
; (Boot eXecution Package) image format in boot/stage2/fs/bxp.asm, which owns
; the bare BXP_ prefix; everything here is prefixed UBXP_/ubxp_.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM flat binary)
; =============================================================================

%include "storage/ubxp/ubxp.inc"

; -----------------------------------------------------------------------------
; Frame Layer
; -----------------------------------------------------------------------------
%include "storage/ubxp/frame/varint.asm"
%include "storage/ubxp/frame/frame.asm"

; -----------------------------------------------------------------------------
; Type Layer
; -----------------------------------------------------------------------------
%include "storage/ubxp/types/primitive.asm"
%include "storage/ubxp/types/bytes.asm"
%include "storage/ubxp/types/nested.asm"
%include "storage/ubxp/types/repeated.asm"
%include "storage/ubxp/types/map.asm"

; -----------------------------------------------------------------------------
; Schema Layer
; -----------------------------------------------------------------------------
%include "storage/ubxp/schema/schema.asm"
%include "storage/ubxp/schema/evolution.asm"
%include "storage/ubxp/schema/unknown.asm"
%include "storage/ubxp/schema/descriptor.asm"
%include "storage/ubxp/schema/canonical.asm"

; -----------------------------------------------------------------------------
; Diagnostics
; -----------------------------------------------------------------------------
%include "storage/ubxp/debug/dump.asm"

section .data
align 8

global ubxp_have_sse42
ubxp_have_sse42:    dq 0            ; Set by ubxp_init; gates CRC32C usage

section .text

global ubxp_init
global ubxp_encode_begin
global ubxp_encode_end

; -----------------------------------------------------------------------------
; ubxp_init
;
; Probes for the SSE4.2 CRC32 instruction that the frame integrity field
; depends on. Encoding without UBXP_FLAG_CRC_PRESENT works regardless; this
; only gates the checksummed path.
;
; Returns:
;   RAX = UBXP_OK, or UBXP_ERR_NODEV when SSE4.2 is unavailable
; -----------------------------------------------------------------------------
align 32
ubxp_init:
    push rbx

    mov eax, 1
    cpuid                           ; Clobbers EAX/EBX/ECX/EDX
    bt ecx, 20                      ; CPUID.01H:ECX[20] = SSE4.2
    jnc .no_sse42

    mov qword [ubxp_have_sse42], 1
    xor eax, eax
    pop rbx
    ret

.no_sse42:
    mov qword [ubxp_have_sse42], 0
    mov rax, UBXP_ERR_NODEV
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_encode_begin
;
; Binds a cursor to a buffer and emits the frame header in one step.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Buffer base pointer
;   RDX = Buffer length in bytes
;   ECX = Schema identifier
;   R8D = UBXP_FLAG_* bitmask
;
; Returns:
;   RAX = Header offset to hand to ubxp_encode_end, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_encode_begin:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; Cursor
    mov r12d, ecx                   ; Schema identifier
    mov r13d, r8d                   ; Flags

    call ubxp_cursor_init           ; RDI/RSI/RDX already in place

    mov rdi, rbx
    mov esi, r12d
    mov edx, r13d
    call ubxp_frame_write_header

    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_encode_end
;
; Back-patches the header and reports the finished frame size.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Header offset from ubxp_encode_begin
;   EDX = Top-level field count
;
; Returns:
;   RAX = Total frame size including the header, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_encode_end:
    push rbx

    mov rbx, rdi
    call ubxp_frame_finalize

    test rax, rax
    js .ee_return                   ; Propagate the failure unchanged

    add rax, UBXP_HEADER_SIZE       ; Body length plus the header itself

.ee_return:
    pop rbx
    ret
