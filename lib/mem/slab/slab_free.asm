; =============================================================================
; Tattva OS — lib/mem/slab/slab_free.asm
; =============================================================================
; Slab Allocator Freeing function stub (Subfeature 10.1).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_SLAB_SLAB_FREE_ASM
%define LIB_MEM_SLAB_SLAB_FREE_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

; -----------------------------------------------------------------------------
; kmem_cache_free — returns an allocated object back to the slab cache
; Input:
;   RDI = pointer to cache descriptor (kmem_cache_t)
;   RSI = pointer to object memory to free
; Output: none
; -----------------------------------------------------------------------------
global kmem_cache_free
kmem_cache_free:
    test rdi, rdi
    jz .exit
    test rsi, rsi
    jz .exit

    push rbx
    push rbp
    push rdi
    push rsi

    ; 1. Derive slab_t descriptor pointer (slab is 4KB page-aligned)
    mov rbx, rsi
    and rbx, -4096                  ; RBX = slab_ptr (metadata head)

    ; 2. Hardening Check: Validate Slab Magic
    cmp qword [rbx + slab_t.magic], 0x51AB51AB
    jne .magic_corrupt_panic

    ; 3. Hardening Check: Verify Slab Redzone
    mov rax, [rdi + kmem_cache_t.obj_size]
    sub rax, 8                      ; RAX = offset of validation bytes
    cmp qword [rsi + rax], 0xDEADC0DE
    jne .redzone_corrupt_panic

    ; 4. Acquire cache spinlock
.lock_spin:
    lock bts qword [rdi + kmem_cache_t.lock], 0
    jc .lock_pause
    jmp .lock_acquired

.lock_pause:
    pause
    test qword [rdi + kmem_cache_t.lock], 1
    jnz .lock_pause
    jmp .lock_spin

.lock_acquired:
    ; 5. Push object back to slab's free_head list
    mov rax, [rbx + slab_t.free_head]
    mov [rsi], rax                  ; Store next pointer inside freed object payload
    mov [rbx + slab_t.free_head], rsi ; Update slab free head to freed object

    dec qword [rbx + slab_t.used_count]

    ; 6. Manage slab list transitions based on new used_count
    mov rax, [rbx + slab_t.used_count]
    test rax, rax
    jz .slab_empty

    ; Check if the slab was full and is now partial (used_count == obj_count - 1)
    mov rcx, [rbx + slab_t.obj_count]
    dec rcx
    cmp rax, rcx
    je .move_full_to_part
    jmp .release_lock

.move_full_to_part:
    push rdi
    push rsi
    push rdx
    push rbx
    mov rsi, kmem_cache_t.slabs_full
    mov rdx, rbx                    ; Slab pointer
    call kmem_slab_unlink
    pop rbx
    pop rdx
    pop rsi
    pop rdi

    push rdi
    push rsi
    push rdx
    push rbx
    mov rsi, kmem_cache_t.slabs_part
    mov rdx, rbx
    call kmem_slab_link
    pop rbx
    pop rdx
    pop rsi
    pop rdi
    jmp .release_lock

.slab_empty:
    ; Move empty slab to slabs_free list (unlink from slabs_part or slabs_full)
    mov rcx, [rbx + slab_t.obj_count]
    cmp rcx, 1
    je .unlink_full

    push rdi
    push rsi
    push rdx
    push rbx
    mov rsi, kmem_cache_t.slabs_part
    mov rdx, rbx
    call kmem_slab_unlink
    pop rbx
    pop rdx
    pop rsi
    pop rdi
    jmp .link_free

.unlink_full:
    push rdi
    push rsi
    push rdx
    push rbx
    mov rsi, kmem_cache_t.slabs_full
    mov rdx, rbx
    call kmem_slab_unlink
    pop rbx
    pop rdx
    pop rsi
    pop rdi

.link_free:
    push rdi
    push rsi
    push rdx
    push rbx
    mov rsi, kmem_cache_t.slabs_free
    mov rdx, rbx
    call kmem_slab_link
    pop rbx
    pop rdx
    pop rsi
    pop rdi

.release_lock:
    mov qword [rdi + kmem_cache_t.lock], 0

    pop rsi
    pop rdi
    pop rbp
    pop rbx
.exit:
    ret

.magic_corrupt_panic:
    lea rdi, [msg_magic_corrupt_reason]
    xor rsi, rsi
    call kernel_panic
    cli
.halt_magic:
    hlt
    jmp .halt_magic

.redzone_corrupt_panic:
    lea rdi, [msg_redzone_corrupt_reason]
    xor rsi, rsi
    call kernel_panic
    cli
.halt_redzone:
    hlt
    jmp .halt_redzone

section .data
msg_magic_corrupt_reason:   db "KERNEL PANIC: Slab descriptor magic metadata corruption detected!", 0
msg_redzone_corrupt_reason: db "KERNEL PANIC: Slab redzone byte buffer overflow/corruption detected!", 0

%endif ; LIB_MEM_SLAB_SLAB_FREE_ASM
