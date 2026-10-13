; ============================================================================
; Replay Test — Deterministic Protocol Session Replay
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"

extern tv_fs_read
extern tv_fs_open
extern tv_fs_pread
extern tv_fs_close
extern wire_decode_header
extern dispatch_call
extern arena_init
extern arena_alloc

section .text

; ---------------------------------------------------------------------------
; replay_run
;   Run a recorded protocol session (.cwprec file)
;   IN:  rdi = replay_file_path, rsi = arena
;   OUT: rax = 0 pass, 1 fail
; ---------------------------------------------------------------------------
global replay_run
replay_run:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi        ; file path
    mov r12, rsi        ; arena
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Open replay file
    mov rdi, rbx
    call tv_fs_open
    test rax, rax
    js .fail
    mov r13, rax        ; file handle

    ; Read header
    sub rsp, 32
    mov rdi, r13
    mov rsi, rsp
    mov rdx, 32
    mov rcx, 0
    call tv_fs_pread
    test rax, rax
    js .fail_close

    ; Verify magic "CWPR"
    cmp dword [rsp], 0x52505743  ; "CWPR"
    jne .fail_close

    ; Version
    mov eax, [rsp + 4]
    cmp eax, 1
    jne .fail_close

    ; Frame count
    mov r14, [rsp + 8]

    ; Initialize dispatch
    ; TODO: Initialize server state for replay

.replay_loop:
    test r14, r14
    jz .done

    ; Read frame header
    ; struct FrameHdr { timestamp: u64, msg_count: u32, msg_bytes: u32 }
    sub rsp, 16
    mov rdi, r13
    mov rsi, rsp
    mov rdx, 16
    mov rcx, [rsp + 24]  ; current offset
    call tv_fs_pread
    test rax, rax
    js .fail_close

    mov r15, [rsp]       ; timestamp
    mov eax, [rsp + 8]   ; msg_count
    mov r14d, [rsp + 12] ; msg_bytes

    ; Read messages
    sub rsp, 4096
    mov rdi, r13
    mov rsi, rsp
    mov rdx, r14d
    mov rcx, [rsp + 24]  ; offset
    add rcx, 16
    call tv_fs_pread
    test rax, rax
    js .fail_close

    ; Process messages
    mov r12, rsp
    mov r13d, [rsp + 8]  ; msg_count (from frame header)

.msg_loop:
    test r13d, r13d
    jz .frame_done

    ; Decode message
    mov rdi, r12
    sub rsp, 12
    mov rsi, rsp
    call wire_decode_header
    test rax, rax
    jnz .fail_close

    ; Dispatch
    ; TODO: Call dispatch_call with decoded message

    ; Advance to next message
    mov eax, [rsp + 8]   ; payload len
    add rax, 12
    add r12, rax
    dec r13d
    jmp .msg_loop

.frame_done:
    dec r14              ; frame count
    jmp .replay_loop

.done:
    add rsp, 32
    mov rdi, r13
    call tv_fs_close
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.fail_close:
    mov rdi, r13
    call tv_fs_close
.fail:
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global replay_test_version
replay_test_version: dq 0x010000