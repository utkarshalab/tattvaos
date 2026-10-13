; ============================================================================
; Regions — Opaque and Input Region Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

; ---------------------------------------------------------------------------
; regions_init
;   Initialize region subsystem
; ---------------------------------------------------------------------------
global regions_init
regions_init:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; regions_create
;   Create region object
;   IN:  rdi = server*, rsi = client*
;   OUT: rax = region_handle, negative error
; ---------------------------------------------------------------------------
global regions_create
regions_create:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate region
    mov rdi, [rbx + Server.arena]
    mov rsi, [rbx + Server.arena]
    mov rdx, 8
    call region_init
    test rax, rax
    jz .oom

    ; Create handle
    mov rdi, [rbx + Server.region_table]
    mov rsi, rax
    call handle_create
    test rax, rax
    jnz .ok

    ; Cleanup on handle failure
    mov rdi, rax
    call region_destroy
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

.ok:
    mov qword [rbx + Server.region_table], rax
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; regions_destroy
;   Destroy region
; ---------------------------------------------------------------------------
global regions_destroy
regions_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov rdi, [rbx + Server.region_table]
    mov rsi, r12
    call handle_resolve
    test rax, rax
    jz .not_found

    mov rdi, rax
    call region_destroy

    mov rdi, [rbx + Server.region_table]
    mov rsi, r12
    call handle_destroy

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.not_found:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; regions_add
;   Add rect to region
; ---------------------------------------------------------------------------
global regions_add
regions_add:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    mov r12, r9
    ASSERT_PTR rbx

    mov rdi, [rbx + Server.region_table]
    mov rsi, r12
    call handle_resolve
    test rax, rax
    jz .not_found

    mov rdi, rax
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    mov r8, r9
    call region_add_rect
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.not_found:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; regions_subtract
;   Subtract rect from region
; ---------------------------------------------------------------------------
global regions_subtract
regions_subtract:
    PROLOGUE
    ; TODO
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; regions_clear
;   Clear region
; ---------------------------------------------------------------------------
global regions_clear
regions_clear:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov rdi, [rbx + Server.region_table]
    mov rsi, r12
    call handle_resolve
    test rax, rax
    jz .not_found

    mov rdi, rax
    call region_clear

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.not_found:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; regions_get_rects
;   Get region rectangles
; ---------------------------------------------------------------------------
global regions_get_rects
regions_get_rects:
    PROLOGUE
    ; TODO
    xor rax, rax
    leave
    ret

section .data
global regions_version
regions_version: dq 0x010000
