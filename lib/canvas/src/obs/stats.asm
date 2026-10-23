; ============================================================================
; Stats — Per-Client Statistics (frames, latency, memory, errors)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/canvas_client.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc

; struct offsets (hoisted above use)
%define ClientStats_SIZE    104

section .text

; ClientStats struct layout (manual offsets)
; Offsets defined in inc/struct_offsets.inc
; ----------

; ---------------------------------------------------------------------------
; stats_init
; ---------------------------------------------------------------------------
global stats_init
stats_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov qword [rbx + Server.client_stats], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; stats_create
;   Allocate stats for a client
; ---------------------------------------------------------------------------
global stats_create
stats_create:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Server.arena]
    mov rsi, ClientStats_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov qword [rbx + ClientStats.client_id], r12
    mov qword [rbx + ClientStats.frames], 0
    mov qword [rbx + ClientStats.commits], 0
    mov qword [rbx + ClientStats.damages], 0
    mov qword [rbx + ClientStats.events_in], 0
    mov qword [rbx + ClientStats.events_out], 0
    mov qword [rbx + ClientStats.bytes_in], 0
    mov qword [rbx + ClientStats.bytes_out], 0
    mov qword [rbx + ClientStats.proto_errors], 0
    mov qword [rbx + ClientStats.last_commit], 0
    mov qword [rbx + ClientStats.last_present], 0
    mov qword [rbx + ClientStats.commit_to_present_ns], 0
    mov qword [rbx + ClientStats.mem_bytes], 0
    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; stats_inc
;   IN: rdi = stats*, rsi = field_offset
; ---------------------------------------------------------------------------
global stats_inc
stats_inc:
    PROLOGUE
    ASSERT_PTR rdi
    inc qword [rdi + rsi]
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; stats_add
;   IN: rdi = stats*, rsi = field_offset, rdx = delta
; ---------------------------------------------------------------------------
global stats_add
stats_add:
    PROLOGUE
    ASSERT_PTR rdi
    add [rdi + rsi], rdx
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; stats_commit
; ---------------------------------------------------------------------------
global stats_commit
stats_commit:
    PROLOGUE
    ASSERT_PTR rdi
    inc qword [rdi + ClientStats.commits]
    call ut_time_now_ns
    mov [rdi + ClientStats.last_commit], rax
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; stats_present
; ---------------------------------------------------------------------------
global stats_present
stats_present:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    inc qword [rbx + ClientStats.frames]
    call ut_time_now_ns
    mov [rbx + ClientStats.last_present], rax
    mov rcx, [rbx + ClientStats.last_commit]
    test rcx, rcx
    jz .done
    sub rax, rcx
    mov [rbx + ClientStats.commit_to_present_ns], rax
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .data
global stats_version
stats_version: dq 0x010000
