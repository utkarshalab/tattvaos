; ============================================================================
; Replay — Deterministic Protocol Session Replay Engine
; Replays .cwprec frames through dispatch; compares frame checksums
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/canvas_client.inc"

extern arena_alloc
%include "inc/struct_offsets.inc"

; struct offsets (hoisted above use)
%define Replayer_SIZE    48

section .text

; Replayer struct layout (manual offsets)
; Offsets defined in inc/struct_offsets.inc
; ----------

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
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

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
    call ut_fs_open
    test rax, rax
    js .open_fail
    mov r12, rax
    ; read header (40 bytes)
    sub rsp, 64
    mov rdi, r12
    mov rsi, rsp
    mov rdx, 40
    xor rcx, rcx
    call ut_fs_pread
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
    call ut_fs_pread
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
    call ut_fs_pread
    cmp rax, r15
    jne .read_fail2
    add r13, r15
    ; Validate the recorded message stream exactly. Protocol dispatch remains
    ; owned by the server loop; replay rejects truncated or over-counted blobs.
    xor r8d, r8d
    xor r9d, r9d
.message_loop:
    cmp r8, r14
    jae .messages_done
    mov rax, r9
    add rax, 12
    cmp rax, r15
    ja .read_fail2
    mov eax, [rsp + r9 + 8]
    add r9, 12
    add r9, rax
    cmp r9, r15
    ja .read_fail2
    inc r8
    jmp .message_loop
.messages_done:
    cmp r8, r14
    jne .read_fail2
    cmp r9, r15
    jne .read_fail2
    mov rax, [rbx + Replayer.frames_done]
    inc qword [rbx + Replayer.frames_done]
    add rsp, 65536
    jmp .frame_loop
.finish:
    mov rdi, r12
    call ut_fs_close
    mov byte [rbx + Replayer.active], 0
    mov rax, [rbx + Replayer.mismatches]
    add rsp, 64
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.bad_magic:
    mov rdi, r12
    call ut_fs_close
    add rsp, 64
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.bad_version:
    mov rdi, r12
    call ut_fs_close
    add rsp, 64
    mov rax, -(ECWP_VERSION)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.read_fail:
    mov rdi, r12
    call ut_fs_close
    add rsp, 64
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.read_fail2:
    mov rdi, r12
    call ut_fs_close
    add rsp, 65536
    add rsp, 64
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.too_big:
    mov rdi, r12
    call ut_fs_close
    add rsp, 64
    mov rax, -(EMSGSIZE)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.open_fail:
    mov byte [rbx + Replayer.active], 0
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.busy:
    mov rax, -(EBUSY)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.none:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

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
    leave
    ret
.none:
    mov qword [rsi], 0
    mov qword [rdx], 0
    mov qword [rcx], 0
    xor rax, rax
    leave
    ret

section .data
global replay_version
replay_version: dq 0x010000
