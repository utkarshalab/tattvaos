; ============================================================================
; Quota — Per-Client Resource Quotas (memory, surfaces, buffers)
; ============================================================================
; quota_take_* / quota_give_*: what each client holds, against its trust
; level's limits (QA-06): trusted none; standard and others 512 MiB of
; buffer pixels, 64 surfaces, 32 buffers; sandboxed 128 MiB, 16, 8, as its
; trust profile states. Without them one client could take the memory, or
; fill the server-wide handle tables, every other client needs.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/canvas_client.inc"
%include "inc/caps.inc"

extern arena_alloc

section .text

; ---------------------------------------------------------------------------
; quota_init
; ---------------------------------------------------------------------------
global quota_init
quota_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.quotas], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; quota_create
;   Create quota from trust profile
; ---------------------------------------------------------------------------
global quota_create
quota_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov rdi, [rbx + Server.arena]
    mov rsi, Quota_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov rax, [r13 + TrustProfile.quota_mem]
    mov [rbx + Quota.max_mem], rax
    mov qword [rbx + Quota.used_mem], 0
    mov eax, [r13 + TrustProfile.quota_surfs]
    mov [rbx + Quota.max_surfs], eax
    mov dword [rbx + Quota.used_surfs], 0
    mov eax, [r13 + TrustProfile.quota_buffers]
    mov [rbx + Quota.max_bufs], eax
    mov dword [rbx + Quota.used_bufs], 0
    mov dword [rbx + Quota.max_objs], 65536
    mov dword [rbx + Quota.used_objs], 0
    mov qword [rbx + Quota.client], r12

    mov qword [r12 + Client.quota], rbx
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; quota_check_mem
; ---------------------------------------------------------------------------
global quota_check_mem
quota_check_mem:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; 0 max = unlimited
    mov rax, [rbx + Quota.max_mem]
    test rax, rax
    jz .ok
    mov rcx, [rbx + Quota.used_mem]
    add rcx, r12
    cmp rcx, rax
    ja .exceeded
.ok:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.exceeded:
    mov rax, -(EQUOTA_MEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; quota_alloc_mem
; ---------------------------------------------------------------------------
global quota_alloc_mem
quota_alloc_mem:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    call quota_check_mem
    test rax, rax
    jnz .fail
    add qword [rbx + Quota.used_mem], r12
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.fail:
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; quota_free_mem
; ---------------------------------------------------------------------------
global quota_free_mem
quota_free_mem:
    PROLOGUE
    ASSERT_PTR rdi
    sub qword [rdi + Quota.used_mem], rsi
    jns .ok
    mov qword [rdi + Quota.used_mem], 0
.ok:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; quota_check_surfs
; ---------------------------------------------------------------------------
global quota_check_surfs
quota_check_surfs:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Quota.max_surfs]
    test eax, eax
    jz .ok
    cmp dword [rdi + Quota.used_surfs], eax
    jae .exceeded
.ok:
    xor rax, rax
    leave
    ret
.exceeded:
    mov rax, -(EQUOTA_SURF)
    leave
    ret

; ---------------------------------------------------------------------------
; quota_alloc_surf
; ---------------------------------------------------------------------------
global quota_alloc_surf
quota_alloc_surf:
    PROLOGUE
    ASSERT_PTR rdi
    call quota_check_surfs
    test rax, rax
    jnz .fail
    inc dword [rdi + Quota.used_surfs]
    xor rax, rax
    leave
    ret
.fail:
    leave
    ret

; ---------------------------------------------------------------------------
; quota_free_surf
; ---------------------------------------------------------------------------
global quota_free_surf
quota_free_surf:
    PROLOGUE
    ASSERT_PTR rdi
    dec dword [rdi + Quota.used_surfs]
    jns .ok
    mov dword [rdi + Quota.used_surfs], 0
.ok:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; quota_check_bufs
; ---------------------------------------------------------------------------
global quota_check_bufs
quota_check_bufs:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Quota.max_bufs]
    test eax, eax
    jz .ok
    cmp dword [rdi + Quota.used_bufs], eax
    jae .exceeded
.ok:
    xor rax, rax
    leave
    ret
.exceeded:
    mov rax, -(EQUOTA_SURF)
    leave
    ret

; ---------------------------------------------------------------------------
; quota_alloc_buf
; ---------------------------------------------------------------------------
global quota_alloc_buf
quota_alloc_buf:
    PROLOGUE
    ASSERT_PTR rdi
    call quota_check_bufs
    test rax, rax
    jnz .fail
    inc dword [rdi + Quota.used_bufs]
    xor rax, rax
    leave
    ret
.fail:
    leave
    ret

; ---------------------------------------------------------------------------
; quota_free_buf
; ---------------------------------------------------------------------------
global quota_free_buf
quota_free_buf:
    PROLOGUE
    ASSERT_PTR rdi
    dec dword [rdi + Quota.used_bufs]
    jns .ok
    mov dword [rdi + Quota.used_bufs], 0
.ok:
    xor rax, rax
    leave
    ret

; client_limits' columns
%define LIMIT_PIXELS    0
%define LIMIT_SURFACES  8
%define LIMIT_BUFFERS   12

; ---------------------------------------------------------------------------
; quota_take_buffer / quota_give_buffer
;   A buffer of a client's: taken if within its count and pixel limits,
;   given back when it goes
;   IN:  rdi = client*, rsi = its pixels' bytes
;   OUT: rax = 0, -EQUOTA_BUF too many, -EQUOTA_MEM too many bytes (take)
; ---------------------------------------------------------------------------
global quota_take_buffer
quota_take_buffer:
    call limits_of                      ; -> rdx = the client's limits
    mov eax, [rdi + Client.used_buffers]
    cmp dword [rdx + LIMIT_BUFFERS], 0
    je .count_ok
    cmp eax, [rdx + LIMIT_BUFFERS]
    jae .count
.count_ok:
    mov rax, [rdi + Client.used_pixels]
    add rax, rsi
    jc .bytes
    cmp qword [rdx + LIMIT_PIXELS], 0
    je .bytes_ok
    cmp rax, [rdx + LIMIT_PIXELS]
    ja .bytes
.bytes_ok:
    mov [rdi + Client.used_pixels], rax
    inc dword [rdi + Client.used_buffers]
    xor eax, eax
    ret
.count:
    mov rax, -(EQUOTA_BUF)
    ret
.bytes:
    mov rax, -(EQUOTA_MEM)
    ret

global quota_give_buffer
quota_give_buffer:
    sub [rdi + Client.used_pixels], rsi
    dec dword [rdi + Client.used_buffers]
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; quota_take_surface / quota_give_surface
;   IN:  rdi = client*
;   OUT: rax = 0, -EQUOTA_SURF too many (take)
; ---------------------------------------------------------------------------
global quota_take_surface
quota_take_surface:
    call limits_of
    mov eax, [rdi + Client.used_surfaces]
    cmp dword [rdx + LIMIT_SURFACES], 0
    je .ok
    cmp eax, [rdx + LIMIT_SURFACES]
    jae .over
.ok:
    inc dword [rdi + Client.used_surfaces]
    xor eax, eax
    ret
.over:
    mov rax, -(EQUOTA_SURF)
    ret

global quota_give_surface
quota_give_surface:
    dec dword [rdi + Client.used_surfaces]
    xor eax, eax
    ret

; rdi = client* -> rdx = its trust level's row of client_limits (an unknown
; level gets the standard one); rdi, rsi kept
limits_of:
    mov rax, [rdi + Client.trust_profile]
    cmp rax, TRUST_KIOSK
    jbe .known
    mov eax, TRUST_STANDARD
.known:
    lea rdx, [rel client_limits]
    shl rax, 4
    add rdx, rax
    ret

section .rodata
; by trust level: pixels' bytes, surfaces, buffers (0: no limit)
align 8
client_limits:
    dq 0
    dd 0, 0                             ; trusted
    dq 512 * 1024 * 1024
    dd 64, 32                           ; standard
    dq 128 * 1024 * 1024
    dd 16, 8                            ; sandboxed
    dq 512 * 1024 * 1024
    dd 64, 32                           ; remote
    dq 512 * 1024 * 1024
    dd 64, 32                           ; kiosk

section .data
global quota_version
quota_version: dq 0x010000
