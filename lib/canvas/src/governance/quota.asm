; ============================================================================
; Quota — Per-Client Resource Quotas (memory, surfaces, buffers)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/canvas_client.inc"

extern arena_alloc

; struct offsets (hoisted above use)
%define Quota_SIZE    56

section .text

struc Quota
    .max_mem:        resq 1
    .used_mem:       resq 1
    .max_surfs:      resd 1
    .used_surfs:     resd 1
    .max_bufs:       resd 1
    .used_bufs:      resd 1
    .max_objs:       resd 1
    .used_objs:      resd 1
    .client:         resq 1
endstruc

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

section .data
global quota_version
quota_version: dq 0x010000
