; =============================================================================
; Tattva OS — lib/mem/virt/balloon.asm
; =============================================================================
; Memory Balloon Driver.
; Dynamically allocates (inflates) or frees (deflates) page frames to adjust guest
; memory footprint on hypervisor requests.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_BALLOON_ASM
%define LIB_MEM_VIRT_BALLOON_ASM

[BITS 64]

; Maximum pages the balloon can allocate/hold
BALLOON_MAX_PAGES equ 1024

section .text

; -----------------------------------------------------------------------------
; virt_balloon_inflate — inflates the balloon by allocating page frames from guest
; Input:
;   RDI = number of pages to inflate
; Output:
;   RAX = actual number of pages successfully inflated
; -----------------------------------------------------------------------------
global virt_balloon_inflate
virt_balloon_inflate:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13

    mov r12, rdi                    ; R12 = requested pages to inflate
    xor r13, r13                    ; R13 = count of successfully inflated pages

.loop:
    cmp r13, r12
    jae .done                       ; Done inflating requested pages

    ; Check if balloon array is full
    mov rax, [sys_balloon_current_pages]
    cmp rax, BALLOON_MAX_PAGES
    jae .done

    ; Allocate a physical page frame
    extern phys_alloc_page
    call phys_alloc_page
    test rax, rax
    jz .done                        ; OOM, stop inflation

    ; Store page frame physical address in array
    mov rbx, [sys_balloon_current_pages]
    shl rbx, 3                      ; index * 8
    lea rcx, [sys_balloon_page_array]
    mov [rcx + rbx], rax

    ; Update current pages count
    inc qword [sys_balloon_current_pages]
    inc r13
    jmp .loop

.done:
    mov rax, r13
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_balloon_deflate — deflates the balloon by returning page frames to guest
; Input:
;   RDI = number of pages to deflate
; Output:
;   RAX = actual number of pages successfully deflated
; -----------------------------------------------------------------------------
global virt_balloon_deflate
virt_balloon_deflate:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13

    mov r12, rdi                    ; R12 = requested pages to deflate
    xor r13, r13                    ; R13 = count of successfully deflated pages

.loop:
    cmp r13, r12
    jae .done                       ; Done deflating requested pages

    ; Check if balloon is already empty
    mov rax, [sys_balloon_current_pages]
    test rax, rax
    jz .done

    ; Pop page frame from array
    dec rax
    mov [sys_balloon_current_pages], rax
    shl rax, 3                      ; index * 8
    lea rbx, [sys_balloon_page_array]
    mov rdi, [rbx + rax]            ; RDI = physical page address to free
    mov qword [rbx + rax], 0        ; clear slot

    ; Free the page frame
    extern phys_free_page
    call phys_free_page

    inc r13
    jmp .loop

.done:
    mov rax, r13
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_balloon_adjust — reconciles current balloon size with target balloon size
; Input:  none
; Output:
;   RAX = final current balloon pages
; -----------------------------------------------------------------------------
global virt_balloon_adjust
virt_balloon_adjust:
    push rbx
    push rcx
    push rdi
    push rsi

    mov rax, [sys_balloon_target_pages]
    mov rbx, [sys_balloon_current_pages]
    cmp rbx, rax
    je .no_change
    jb .inflate

.deflate:
    ; current > target, deflate the difference
    mov rdi, rbx
    sub rdi, rax                    ; RDI = current - target
    call virt_balloon_deflate
    jmp .done

.inflate:
    ; current < target, inflate the difference
    mov rdi, rax
    sub rdi, rbx                    ; RDI = target - current
    call virt_balloon_inflate
    jmp .done

.no_change:
.done:
    mov rax, [sys_balloon_current_pages]
    pop rsi
    pop rdi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_balloon_set_target — sets target balloon size and triggers adjustment
; Input:
;   RDI = new target balloon size in pages
; Output:
;   RAX = final current balloon pages
; -----------------------------------------------------------------------------
global virt_balloon_set_target
virt_balloon_set_target:
    mov [sys_balloon_target_pages], rdi
    call virt_balloon_adjust
    ret

section .data

align 8
global sys_balloon_target_pages
global sys_balloon_current_pages

sys_balloon_target_pages:   dq 0
sys_balloon_current_pages:  dq 0

section .bss

align 8
global sys_balloon_page_array

sys_balloon_page_array:     resq BALLOON_MAX_PAGES

%endif ; LIB_MEM_VIRT_BALLOON_ASM
