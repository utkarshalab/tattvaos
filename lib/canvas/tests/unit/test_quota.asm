; ============================================================================
; Unit Test — Client Quotas (src/governance/quota.asm)
; ============================================================================
; test_quota_suite -> eax = failed cases (each case returns 0 / 1).
; Memory, surface and buffer limits: within, at and over the limit, 0 meaning
; unlimited, frees flooring at zero, and creation from a trust profile.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"

extern arena_init
extern quota_create
extern quota_check_mem
extern quota_alloc_mem
extern quota_free_mem
extern quota_alloc_surf
extern quota_free_surf
extern quota_alloc_buf
extern quota_free_buf

%define HEAP_SIZE 16384

section .text

global test_quota_suite
global test_quota_main
test_quota_suite:
test_quota_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call fresh
    call %1
    add ebx, eax
%endmacro
    CASE tq_mem_limit
    CASE tq_mem_unlimited
    CASE tq_mem_free
    CASE tq_surfs
    CASE tq_bufs
    CASE tq_surf_unlimited
    CASE tq_create
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

; limits: 1000 bytes, 2 surfaces, 2 buffers; nothing used
fresh:
    lea rdi, [rel quota]
    xor eax, eax
    mov ecx, Quota_size
    rep stosb
    mov qword [rel quota + Quota.max_mem], 1000
    mov dword [rel quota + Quota.max_surfs], 2
    mov dword [rel quota + Quota.max_bufs], 2
    ret

%macro MEM 2                            ; quota_%1_mem of %2 bytes
    lea rdi, [rel quota]
    mov esi, %2
    call quota_%1_mem
%endmacro
%macro ONE 1                            ; quota_%1 on the quota
    lea rdi, [rel quota]
    call quota_%1
%endmacro

tq_mem_limit:
    sub rsp, 8
    MEM alloc, 600
    test rax, rax
    jnz .fail
    MEM alloc, 400                      ; exactly the limit
    test rax, rax
    jnz .fail
    MEM check, 1
    cmp rax, -(EQUOTA_MEM)
    jne .fail
    MEM alloc, 1
    cmp rax, -(EQUOTA_MEM)
    jne .fail
    cmp qword [rel quota + Quota.used_mem], 1000
    jne .fail
    PASS

tq_mem_unlimited:
    sub rsp, 8
    mov qword [rel quota + Quota.max_mem], 0
    MEM alloc, 1000000
    test rax, rax
    jnz .fail
    PASS

tq_mem_free:
    sub rsp, 8
    MEM alloc, 500
    MEM free, 200
    cmp qword [rel quota + Quota.used_mem], 300
    jne .fail
    MEM free, 400                       ; more than used: floors at zero
    cmp qword [rel quota + Quota.used_mem], 0
    jne .fail
    PASS

tq_surfs:
    sub rsp, 8
    ONE alloc_surf
    ONE alloc_surf
    test rax, rax
    jnz .fail
    ONE alloc_surf
    cmp rax, -(EQUOTA_SURF)
    jne .fail
    ONE free_surf
    ONE alloc_surf
    test rax, rax
    jnz .fail
    PASS

tq_bufs:
    sub rsp, 8
    ONE alloc_buf
    ONE alloc_buf
    test rax, rax
    jnz .fail
    ONE alloc_buf
    test rax, rax
    jns .fail
    ONE free_buf
    ONE free_buf
    ONE free_buf                        ; one too many: floors at zero
    cmp dword [rel quota + Quota.used_bufs], 0
    jne .fail
    PASS

tq_surf_unlimited:
    sub rsp, 8
    mov dword [rel quota + Quota.max_surfs], 0
    mov dword [rel quota + Quota.used_surfs], 100000
    ONE alloc_surf
    test rax, rax
    jnz .fail
    PASS

tq_create:
    sub rsp, 8
    lea rdi, [rel arena]
    lea rsi, [rel heap]
    mov edx, HEAP_SIZE
    call arena_init
    lea rax, [rel arena]
    mov [rel server + Server.arena], rax
    mov qword [rel profile + TrustProfile.quota_mem], 4096
    mov dword [rel profile + TrustProfile.quota_surfs], 7
    mov dword [rel profile + TrustProfile.quota_buffers], 9
    lea rdi, [rel server]
    lea rsi, [rel client]
    lea rdx, [rel profile]
    call quota_create
    test rax, rax
    jnz .fail
    mov rcx, [rel client + Client.quota]
    test rcx, rcx
    jz .fail
    cmp qword [rcx + Quota.max_mem], 4096
    jne .fail
    cmp dword [rcx + Quota.max_surfs], 7
    jne .fail
    cmp dword [rcx + Quota.max_bufs], 9
    jne .fail
    lea rax, [rel client]
    cmp [rcx + Quota.client], rax
    jne .fail
    PASS


section .bss
alignb 16
quota:      resb Quota_size
server:     resb Server_size
client:     resb Client_size
profile:    resb TrustProfile_size
arena:      resb Arena_size
alignb 16
heap:       resb HEAP_SIZE
