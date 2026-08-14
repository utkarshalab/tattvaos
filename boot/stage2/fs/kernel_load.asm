; =============================================================================
; Tattva OS — boot/stage2/fs/kernel_load.asm
; =============================================================================
; Relocates an already-loaded ULF image to a different physical address.
;
; This used to be the loader: it copied a fixed 64KB from the KERNEL_TEMP
; bounce buffer up to 1MB, which was the whole kernel back when the kernel was
; a stub. It is no longer on the boot path — kernel_stream.asm reads the image
; straight to KERNEL_LOAD in real mode through a flat ES window, because a
; 9.3MB image neither fits in the bounce buffer nor can be described by a
; compile-time sector count.
;
; What remains is the relocation step KASLR needs: move the image that is
; already sitting at KERNEL_LOAD somewhere else. The length comes from the ULF
; header rather than a constant, so it tracks the image instead of rotting
; against it.
;
; Author:  Utkarsha Labs
; Target:  x86-64, long mode (64-bit)
; =============================================================================

%ifndef KERNEL_LOAD_ASM
%define KERNEL_LOAD_ASM

[BITS 64]

; =============================================================================
; kernel_load — copy the ULF image from KERNEL_LOAD to a new physical address
; Input:  RDI = destination physical address (0 means KERNEL_LOAD, a no-op)
; Output: none
; Clobbers: none (preserves all)
; =============================================================================
kernel_load:
    push rsi
    push rdi
    push rcx
    push rax
    cld                             ; forward copy for rep movsq

    mov rsi, KERNEL_LOAD            ; source: where the streaming loader put it

    test rdi, rdi
    jnz .have_dest
    mov rdi, KERNEL_LOAD
.have_dest:
    cmp rdi, rsi
    je .done                        ; relocating onto itself

    ; Length from the ULF header (+4), rounded up to a whole quadword. The
    ; caller has already checked the magic, so the field is trustworthy here.
    xor rcx, rcx
    mov ecx, [rsi + 4]
    add rcx, 7
    shr rcx, 3                      ; quadwords to move
    jz .done

    ; Copy backwards when the regions overlap forwards, so a relocation to a
    ; slightly higher address does not overwrite source it has not read yet.
    mov rax, rdi
    sub rax, rsi
    cmp rax, 0
    jle .forward                    ; dest below source: forward is safe

.backward:
    std
    lea rsi, [rsi + rcx * 8 - 8]
    lea rdi, [rdi + rcx * 8 - 8]
    rep movsq
    cld
    jmp .done

.forward:
    rep movsq

.done:
    pop rax
    pop rcx
    pop rdi
    pop rsi
    ret

[BITS 16]

%endif ; KERNEL_LOAD_ASM
