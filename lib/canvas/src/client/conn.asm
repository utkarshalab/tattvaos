; ============================================================================
; Client Conn — Connection Setup (channel pair + handshake)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/canvas_client.inc"

extern arena_init

; ClientConn struct layout (manual offsets to avoid NASM preprocessor issues)
%define CLIENT_REGION_SIZE        1048576
%define CLIENT_HEAP_OFFSET        65536

; ---------------------------------------------------------------------------
; canvas_connect
;   IN: rdi = caps_wanted u64 — OUT: rax = conn* (0 on fail)
; ---------------------------------------------------------------------------
global canvas_connect
canvas_connect:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov rdi, CLIENT_REGION_SIZE
    mov rsi, 0
    call ut_mem_alloc
    test rax, rax
    js .fail
    mov r12, rax
    mov [r12 + ClientConn.region_handle], r8
    mov qword [r12 + ClientConn.server_chan], 0
    mov qword [r12 + ClientConn.caps_wanted], rbx
    mov qword [r12 + ClientConn.caps_granted], 0
    mov dword [r12 + ClientConn.next_obj], 1
    mov qword [r12 + ClientConn.buffer_count], 0
    mov qword [r12 + ClientConn.clip_len], 0
    mov qword [r12 + ClientConn.clip_mime_len], 0
    mov byte [r12 + ClientConn.present_valid], 0
    lea rax, [r12 + ClientConn.arena_state]
    mov [r12 + ClientConn.arena], rax
    mov rdi, rax
    lea rsi, [r12 + CLIENT_HEAP_OFFSET]
    mov rdx, CLIENT_REGION_SIZE - CLIENT_HEAP_OFFSET
    call arena_init
    test rax, rax
    js .free_fail
    ; Canvas clients are native peers. Capabilities are negotiated by intersecting
    ; with the capabilities implemented by this library instance.
    mov rax, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE | CLIENT_CAP_PRESENT | CLIENT_CAP_SHELL | CLIENT_CAP_DATA
    and rbx, rax
    mov qword [r12 + ClientConn.caps_granted], rbx
    mov rax, r12
    EPILOGUE_RESTORE rbx, r12
    ret
.fail:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.free_fail:
    mov rdi, [r12 + ClientConn.region_handle]
    call ut_mem_free
    jmp .fail

; ---------------------------------------------------------------------------
; canvas_disconnect
; ---------------------------------------------------------------------------
global canvas_disconnect
canvas_disconnect:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov rdi, [rbx + ClientConn.region_handle]
    call ut_mem_free
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; canvas_get_caps
; ---------------------------------------------------------------------------
global canvas_get_caps
canvas_get_caps:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + ClientConn.caps_granted]
    leave
    ret

section .data
global canvas_conn_version
canvas_conn_version: dq 0x010000
