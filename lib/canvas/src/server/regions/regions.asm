; ============================================================================
; Regions — Opaque and Input Region Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

section .text

; ---------------------------------------------------------------------------
; regions_init
;   Initialize region subsystem
; ---------------------------------------------------------------------------
global regions_init
regions_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, r12
    mov rsi, 48
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax
    mov rdi, r13
    mov rsi, r12
    mov rdx, 1024
    call handle_table_init
    test rax, rax
    js .done
    mov [rbx + Server.region_table], r13
.done:
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; regions_create
;   Create region object
;   IN:  rdi = server*, rsi = client*
;   OUT: rax = region_handle, negative error
; ---------------------------------------------------------------------------
global regions_create
regions_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate region
    mov rdi, [rbx + Server.arena]
    call region_init
    test rax, rax
    jz .oom

    ; Create handle
    mov r13, rax
    mov rdi, [rbx + Server.region_table]
    mov rsi, r13
    call handle_create
    test rax, rax
    jnz .ok

    ; Cleanup on handle failure
    mov rdi, r13
    call region_destroy
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.ok:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
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
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi                  ; handle
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    mov [rsp + 12], r9d
    ASSERT_PTR rbx

    mov rdi, [rbx + Server.region_table]
    mov rsi, r12
    call handle_resolve
    test rax, rax
    jz .not_found

    mov dword [rsp], r13d
    mov dword [rsp + 4], r14d
    mov dword [rsp + 8], r15d
    mov rdi, rax
    mov rsi, rsp
    call region_add_rect
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.not_found:
    mov rax, -(ENOENT)
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; regions_subtract
;   Subtract rect from region
; ---------------------------------------------------------------------------
global regions_subtract
regions_subtract:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    mov [rsp + 12], r9d
    mov rdi, [rbx + Server.region_table]
    mov rsi, r12
    call handle_resolve
    test rax, rax
    jz .not_found
    mov dword [rsp], r13d
    mov dword [rsp + 4], r14d
    mov dword [rsp + 8], r15d
    mov rdi, rax
    mov rsi, rsp
    call region_subtract_rect
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.not_found:
    mov rax, -(ENOENT)
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
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
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rdx                 ; out rect pointer
    mov r13, rcx                 ; out count
    test r12, r12
    jz .invalid
    test r13, r13
    jz .invalid
    mov rdi, [rbx + Server.region_table]
    call handle_resolve           ; rsi remains handle
    test rax, rax
    jz .not_found
    mov rdx, [rax + Region.rects]
    mov [r12], rdx
    mov rdx, [rax + Region.count]
    mov [r13], rdx
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.not_found:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
global regions_version
regions_version: dq 0x010000
