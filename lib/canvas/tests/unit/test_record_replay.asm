; ============================================================================
; Unit Test — Recording State and Client Stats (src/obs/record.asm, stats.asm)
; ============================================================================
; test_record_replay_suite -> eax = failed cases (each case returns 0 / 1).
; Recording: off with no recorder, follows the recorder's flag. Stats:
; creation, counters by field, commit and present timing.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"

extern arena_init
extern record_is_active
extern stats_create
extern stats_inc
extern stats_add
extern stats_commit
extern stats_present

%define HEAP_SIZE 16384

section .text

global test_record_replay_suite
global test_record_replay_main
test_record_replay_suite:
test_record_replay_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call fresh
    call %1
    add ebx, eax
%endmacro
    CASE tr_inactive
    CASE tr_active
    CASE ts_create
    CASE ts_counters
    CASE ts_commit
    CASE ts_present
    mov eax, ebx
    pop rbx
    ret

%macro PASS 0
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret
%endmacro

fresh:
    sub rsp, 8
    lea rdi, [rel server]
    xor eax, eax
    mov ecx, Server_size
    rep stosb
    lea rdi, [rel arena]
    lea rsi, [rel heap]
    mov edx, HEAP_SIZE
    call arena_init
    lea rax, [rel arena]
    mov [rel server + Server.arena], rax
    add rsp, 8
    ret

; stats for client 42 in rax (callers check it through make_stats)
make_stats:
    sub rsp, 8
    lea rdi, [rel server]
    mov esi, 42
    call stats_create
    add rsp, 8
    ret

tr_inactive:
    sub rsp, 8
    lea rdi, [rel server]
    call record_is_active
    test rax, rax
    jnz .fail
    PASS

tr_active:
    sub rsp, 8
    lea rax, [rel recorder]
    mov [rel server + Server.recorder], rax
    mov byte [rel recorder + Recorder.active], 1
    lea rdi, [rel server]
    call record_is_active
    cmp rax, 1
    jne .fail
    mov byte [rel recorder + Recorder.active], 0
    lea rdi, [rel server]
    call record_is_active
    test rax, rax
    jnz .fail
    PASS

ts_create:
    sub rsp, 8
    call make_stats
    test rax, rax
    jle .fail
    cmp qword [rax + ClientStats.client_id], 42
    jne .fail
    cmp qword [rax + ClientStats.frames], 0
    jne .fail
    PASS

ts_counters:
    push rbx
    call make_stats
    mov rbx, rax
    mov rdi, rbx
    mov esi, ClientStats.events_in
    call stats_inc
    mov rdi, rbx
    mov esi, ClientStats.events_in
    call stats_inc
    mov rdi, rbx
    mov esi, ClientStats.bytes_out
    mov edx, 500
    call stats_add
    xor eax, eax
    cmp qword [rbx + ClientStats.events_in], 2
    setne al
    cmp qword [rbx + ClientStats.bytes_out], 500
    je .done
    mov eax, 1
.done:
    pop rbx
    ret

ts_commit:
    push rbx
    call make_stats
    mov rbx, rax
    mov rdi, rbx
    call stats_commit
    xor eax, eax
    cmp qword [rbx + ClientStats.commits], 1
    setne al
    cmp qword [rbx + ClientStats.last_commit], 0
    jne .done
    mov eax, 1
.done:
    pop rbx
    ret

ts_present:
    push rbx
    call make_stats
    mov rbx, rax
    mov rdi, rbx
    call stats_commit
    mov rdi, rbx
    call stats_present
    xor eax, eax
    cmp qword [rbx + ClientStats.frames], 1
    setne al
    mov rcx, [rbx + ClientStats.last_present]
    cmp rcx, [rbx + ClientStats.last_commit]
    jae .done
    mov eax, 1
.done:
    pop rbx
    ret


section .bss
alignb 16
server:     resb Server_size
recorder:   resb Recorder_size
arena:      resb Arena_size
alignb 16
heap:       resb HEAP_SIZE
