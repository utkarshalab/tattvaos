; ============================================================================
; Replay — Deterministic Protocol Session Replay Engine
; Replays .cwprec frames through dispatch; compares frame checksums
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc Replayer {
    .server:         resq 1
    .active:         resb 1
    .frames_total:   resq 1
    .frames_done:    resq 1
    .mismatches:     resq 1
    .expected_crc:   resq 1
}
%define Replayer_size    48

; ---------------------------------------------------------------------------
; replay_init
; ---------------------------------------------------------------------------
global replay_init
replay_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Server.arena]
    mov rsi, Replayer_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov qword [rbx + Replayer.server], rdi
    mov byte [rbx + Replayer.active], 0
    mov qword [rbx + Replayer.frames_total], 0
    mov qword [rbx + Replayer.frames_done], 0
    mov qword [rbx + Replayer.mismatches], 0
    mov qword [rbx + Replayer.expected_crc], 0
    mov qword [rdi + Server.replayer], rbx
    xor rax, rax
    ret
.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; replay_run_file
;   IN: rdi = server*, rsi = path, rdx = path_len,
;       rcx = expected_crc_array, r8 = expected_count
;   OUT: rax = mismatch count, negative error
; ---------------------------------------------------------------------------
global replay_run_file
replay_run_file:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rax, [rbx + Server.replayer]
    test rax, rax
    jz .none
    mov rbx, rax
    cmp byte [rbx + Replayer.active], 1
    je .busy
    mov byte [rbx + Replayer.active], 1
    mov qword [rbx + Replayer.frames_done], 0
    mov qword [rbx + Replayer.mismatches], 0
    mov qword [rbx + Replayer.expected_crc], r14
    ; open file
    mov rdi, r12
    call tv_fs_open
    test rax, rax
    js .open_fail
    mov r12, rax
    ; read header (40 bytes)
    sub rsp, 64
    mov rdi, r12
    mov rsi, rsp
    mov rdx, 40
    xor rcx, rcx
    call tv_fs_pread
    cmp rax, 40
    jne .read_fail
    cmp dword [rsp + 0], 0x52505743
    jne .bad_magic
    cmp dword [rsp + 4], 1
    jne .bad_version
    mov rax, [rsp + 8]
    mov [rbx + Replayer.frames_total], rax
    ; frame loop
    mov r13, 40  ; file offset
.frame_loop:
    mov rax, [rbx + Replayer.frames_done]
    cmp rax, [rbx + Replayer.frames_total]
    jae .finish
    ; read frame header
    mov rdi, r12
    mov rsi, rsp
    mov rdx, 16
    mov rcx, r13
    call tv_fs_pread
    cmp rax, 16
    jne .read_fail
    mov r14, [rsp + 8]   ; msg_count
    mov r15, [rsp + 12]  ; msg_bytes
    add r13, 16
    ; read blob into arena scratch (cap 64K)
    cmp r15d, 65536
    ja .too_big
    sub rsp, 65536
    mov rdi, r12
    mov rsi, rsp
    mov rdx, r15
    mov rcx, r13
    call tv_fs_pread
    cmp rax, r15
    jne .read_fail2
    add r13, r15
    ; dispatch blob
    ; TODO: walk messages, call dispatch_call per message
    ; then composite + checksum, compare with expected array
    mov rax, [rbx + Replayer.frames_done]
    inc qword [rbx + Replayer.frames_done]
    add rsp, 65536
    jmp .frame_loop
.finish:
    mov rdi, r12
    call tv_fs_close
    mov byte [rbx + Replayer.active], 0
    mov rax, [rbx + Replayer.mismatches]
    add rsp, 64
    ret
.bad_magic:
    mov rdi, r12
    call tv_fs_close
    add rsp, 64
    RETURN_ERROR EINVAL
.bad_version:
    mov rdi, r12
    call tv_fs_close
    add rsp, 64
    RETURN_ERROR ECWP_VERSION
.read_fail:
    mov rdi, r12
    call tv_fs_close
    add rsp, 64
    RETURN_ERROR EIO
.read_fail2:
    mov rdi, r12
    call tv_fs_close
    add rsp, 65536
    add rsp, 64
    RETURN_ERROR EIO
.too_big:
    mov rdi, r12
    call tv_fs_close
    add rsp, 64
    RETURN_ERROR EMSGSIZE
.open_fail:
    mov byte [rbx + Replayer.active], 0
    RETURN_ERROR ENOENT
.busy:
    RETURN_ERROR EBUSY
.none:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; replay_stats
; ---------------------------------------------------------------------------
global replay_stats
replay_stats:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    ASSERT_PTR rdx
    ASSERT_PTR rcx
    mov rax, [rdi + Server.replayer]
    test rax, rax
    jz .none
    mov r8, [rax + Replayer.frames_total]
    mov [rsi], r8
    mov r8, [rax + Replayer.frames_done]
    mov [rdx], r8
    mov r8, [rax + Replayer.mismatches]
    mov [rcx], r8
    xor rax, rax
    ret
.none:
    mov qword [rsi], 0
    mov qword [rdx], 0
    mov qword [rcx], 0
    xor rax, rax
    ret

section .data
global replay_version
replay_version: dq 0x010000
