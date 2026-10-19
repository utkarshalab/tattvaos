; ============================================================================
; Native Planes — Hardware Overlay and Cursor Plane Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

section .text

global native_planes_init
native_planes_init:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov r13, [rbx + Backend.state]
    mov r14, [r13 + Controller.state]
    test r14, r14
    jz .fail_init

    ; Native DCN exposes four universal planes per CRTC.  Keep the count and
    ; allocation bitmap in backend-private state.
    mov dword [r13 + 128], 4
    mov dword [r13 + 132], 0

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.fail_init:
    RETURN_ERROR EIO

global native_plane_assign
native_plane_assign:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov r14, [rbx + Backend.state]
    mov r15, [r14 + Controller.state]
    test r15, r15
    jz .fail_assign

    mov r14, [rbx + Backend.state]
    mov ecx, [r14 + 128]
    mov edx, [r14 + 132]
    xor eax, eax
.find_plane:
    cmp eax, ecx
    jae .no_plane
    bt edx, eax
    jnc .claim
    inc eax
    jmp .find_plane
.claim:
    bts edx, eax
    mov [r14 + 132], edx
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.no_plane:
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.fail_assign:
    RETURN_ERROR EIO

global native_cursor_plane_setup
native_cursor_plane_setup:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov r14, [rbx + Backend.state]
    mov r15, [r14 + Controller.state]
    test r15, r15
    jz .fail_setup

    ; Get CRTC index
    mov eax, [r12 + Output.crtc_index]
    mov r15d, eax

    ; Get MMIO base
    mov r14, [r15 + Controller.mmio_base]

    ; Program cursor plane
    ; CURSOR_SURFACE_ADDRESS
    mov rax, [r13 + Buffer.base]
    mov [r14 + DCN_CURSOR_SURFACE_ADDRESS + r15 * 8], rax

    ; CURSOR_SIZE (typically 64x64)
    mov eax, 64
    mov edx, 64
    shl rdx, 16
    or rax, rdx
    mov [r14 + DCN_CURSOR_SIZE + r15 * 4], rax

    ; CURSOR_POSITION
    mov eax, r14d
    mov edx, r15d
    shl rdx, 16
    or rax, rdx
    mov [r14 + DCN_CURSOR_POSITION + r15 * 4], rax

    ; CURSOR_CONTROL - enable
    mov eax, [r14 + DCN_CURSOR_CONTROL + r15 * 4]
    or eax, 1
    mov [r14 + DCN_CURSOR_CONTROL + r15 * 4], eax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.fail_setup:
    RETURN_ERROR EIO

global native_cursor_move
native_cursor_move:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov r14, [rbx + Backend.state]
    mov r15, [r14 + Controller.state]
    test r15, r15
    jz .fail_move

    ; Get CRTC index
    mov eax, [r12 + Output.crtc_index]
    mov r15d, eax

    ; Get MMIO base
    mov r14, [r15 + Controller.mmio_base]

    ; Update cursor position
    mov eax, r13d
    mov edx, r14d
    shl rdx, 16
    or rax, rdx
    mov [r14 + DCN_CURSOR_POSITION + r15 * 4], rax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.fail_move:
    RETURN_ERROR EIO

section .rodata
DCN_CURSOR_CONTROL:           dd 0x2000
DCN_CURSOR_SURFACE_ADDRESS:   dd 0x2010
DCN_CURSOR_SIZE:              dd 0x2020
DCN_CURSOR_POSITION:          dd 0x2030

section .data
global native_planes_version
native_planes_version: dq 0x010000
