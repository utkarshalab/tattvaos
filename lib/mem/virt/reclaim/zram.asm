; =============================================================================
; Tattva OS — lib/mem/virt/zram.asm
; =============================================================================
; ZRAM Compressed Swap Device backend (Subfeature 28.1).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_ZRAM_ASM
%define LIB_MEM_VIRT_ZRAM_ASM

[BITS 64]

; ZRAM Configuration
ZRAM_MAX_SLOTS   equ 256
ZRAM_MAX_FRAMES  equ (ZRAM_MAX_SLOTS / 2)  ; 128 frames (2 slots per frame)
ZRAM_SLOT_SIZE   equ 2048

; swap_device_t structure definition (must match swap_device.asm)
struc swap_device_t
    .name           resq 1
    .read_page      resq 1
    .write_page     resq 1
    .alloc_slot     resq 1
    .free_slot      resq 1
    .max_slots      resq 1
endstruc

section .text

; External symbols


; -----------------------------------------------------------------------------
; zram_init — clears all metadata and telemetry counts
; -----------------------------------------------------------------------------
global zram_init
zram_init:
    push rdi
    push rcx
    push rax

    ; Clear telemetry
    mov qword [zram_compressed_pages], 0

    ; Zero-out zram_in_use
    lea rdi, [zram_in_use]
    mov rcx, ZRAM_MAX_SLOTS
    xor rax, rax
    cld
    rep stosb

    ; Zero-out zram_sizes
    lea rdi, [zram_sizes]
    mov rcx, ZRAM_MAX_SLOTS
    rep stosw

    ; Zero-out zram_frames
    lea rdi, [zram_frames]
    mov rcx, ZRAM_MAX_FRAMES
    rep stosq

    pop rax
    pop rcx
    pop rdi
    ret

; -----------------------------------------------------------------------------
; zram_alloc_slot — allocates a slot in the ZRAM swap device
; Output:
;   RAX = slot index, or -1 if full
; -----------------------------------------------------------------------------
global zram_alloc_slot
zram_alloc_slot:
    push rbx
    push rcx
    
    lea rcx, [zram_in_use]
    xor rbx, rbx                    ; rbx = slot index loop counter

.loop:
    cmp rbx, ZRAM_MAX_SLOTS
    jge .full

    mov al, [rcx + rbx]
    test al, al
    jz .found

    inc rbx
    jmp .loop

.found:
    mov byte [rcx + rbx], 1         ; reserve slot (write_page will compress)
    mov rax, rbx
    jmp .done

.full:
    mov rax, -1

.done:
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; zram_free_slot — releases a slot and companion physical frame if both free
; Input:
;   RDI = slot index
; Output: none
; -----------------------------------------------------------------------------
global zram_free_slot
zram_free_slot:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; rbx = slot index

    ; Validate slot index
    cmp rbx, ZRAM_MAX_SLOTS
    jae .exit

    lea rcx, [zram_in_use]
    mov al, [rcx + rbx]
    test al, al
    jz .exit                        ; already free

    mov byte [rcx + rbx], 0         ; mark free

    ; Only decrement telemetry if the page was actually compressed/written
    lea rcx, [zram_sizes]
    mov dx, [rcx + rbx * 2]
    test dx, dx
    jz .skip_telemetry_dec

    dec qword [zram_compressed_pages] ; decrement telemetry
    mov word [rcx + rbx * 2], 0     ; clear size

.skip_telemetry_dec:
    ; Frame index = slot / 2
    mov r12, rbx
    shr r12, 1

    ; Check companion slot (rbx ^ 1)
    mov r13, rbx
    xor r13, 1
    mov al, [rcx + r13]
    test al, al
    jnz .exit                       ; companion is in use, keep frame

    ; Companion is also free, release backing physical page frame
    lea rcx, [zram_frames]
    mov rdi, [rcx + r12 * 8]
    test rdi, rdi
    jz .exit

    call phys_free_page

    lea rcx, [zram_frames]
    mov qword [rcx + r12 * 8], 0

.exit:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; zram_write_page — compresses 4KB page using LZ4 and stores to ZRAM slot
; Input:
;   RDI = slot index
;   RSI = src_phys (physical source address)
; Output:
;   RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global zram_write_page
zram_write_page:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; rbx = slot
    mov r12, rsi                    ; r12 = src_phys

    ; Dynamic zpool balancing limit check
    extern zpool_balance
    extern zram_max_slots
    call zpool_balance
    mov rax, [zram_compressed_pages]
    cmp rax, [zram_max_slots]
    jb .under_limit

    ; Limit hit! Trigger physical writeback to evict oldest block (skipping current slot)
    mov rdi, rbx                    ; current slot to skip
    extern zram_writeback
    call zram_writeback
    test rax, rax
    jz .failed                      ; if writeback fails, reject store

.under_limit:

    ; 1. Compress page using lz4_compress to scratch buffer
    mov rdi, r12                    ; src
    lea rsi, [zram_scratch]         ; dest
    mov rdx, ZRAM_SLOT_SIZE         ; max_len (2048)
    call lz4_compress
    
    test rax, rax
    jz .failed                      ; compression failed or size > 2048

    mov r13, rax                    ; r13 = compressed size

    ; Frame index = slot / 2
    mov r14, rbx
    shr r14, 1

    ; Offset = (slot % 2) * 2048
    mov r15, rbx
    and r15, 1
    shl r15, 11

    ; Check if frame is allocated
    lea rcx, [zram_frames]
    mov r8, [rcx + r14 * 8]
    test r8, r8
    jnz .frame_allocated

    ; Allocate physical frame
    call phys_alloc_page
    test rax, rax
    jz .failed

    lea rcx, [zram_frames]
    mov [rcx + r14 * 8], rax
    mov r8, rax

.frame_allocated:
    add r8, r15                     ; dest address = frame + offset

    ; Copy from scratch to slot
    mov rdi, r8
    lea rsi, [zram_scratch]
    mov rdx, r13
    call memcpy

    ; Save compressed size
    lea rcx, [zram_sizes]
    mov [rcx + rbx * 2], r13w

    inc qword [zram_compressed_pages]

    mov rax, 1                      ; success
    jmp .done

.failed:
    ; Free slot if write failed
    mov rdi, rbx
    call zram_free_slot
    xor rax, rax                    ; failure

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; zram_read_page — decompresses LZ4 data from ZRAM slot back to 4KB page
; Input:
;   RDI = slot index
;   RSI = dest_phys (physical destination address)
; Output:
;   RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global zram_read_page
zram_read_page:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; rbx = slot
    mov r12, rsi                    ; r12 = dest_phys

    ; Validate
    cmp rbx, ZRAM_MAX_SLOTS
    jae .err

    lea rcx, [zram_in_use]
    mov al, [rcx + rbx]
    test al, al
    jz .err

    ; Frame index = slot / 2
    mov r13, rbx
    shr r13, 1

    ; Offset = (slot % 2) * 2048
    mov r14, rbx
    and r14, 1
    shl r14, 11

    ; Get physical frame address
    lea rcx, [zram_frames]
    mov r15, [rcx + r13 * 8]
    test r15, r15
    jz .err

    add r15, r14                    ; r15 = compressed data pointer

    ; Get size
    lea rcx, [zram_sizes]
    xor rdx, rdx
    mov dx, [rcx + rbx * 2]         ; rdx = compressed size

    ; Decompress using lz4_decompress
    mov rdi, r15                    ; src
    mov rsi, r12                    ; dest
    call lz4_decompress
    test rax, rax
    jz .err

    ; Free slot
    mov rdi, rbx
    call zram_free_slot

    mov rax, 1                      ; success
    jmp .done

.err:
    xor rax, rax                    ; failure

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; zram_decompress_and_free — direct page-fault helper (mirrors zswap backend)
; Input:
;   RDI = slot index
;   RSI = dest_phys
; Output:
;   RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global zram_decompress_and_free
zram_decompress_and_free:
    ; Redirects directly to zram_read_page
    jmp zram_read_page


section .data

; Telemetry Counter
global zram_compressed_pages
align 8
zram_compressed_pages: dq 0

; ZRAM polymorphic swap device descriptor
align 8
global zram_swap_dev
zram_swap_dev:
    istruc swap_device_t
        at swap_device_t.name,          dq .name_str
        at swap_device_t.read_page,     dq zram_read_page
        at swap_device_t.write_page,    dq zram_write_page
        at swap_device_t.alloc_slot,    dq zram_alloc_slot
        at swap_device_t.free_slot,     dq zram_free_slot
        at swap_device_t.max_slots,     dq ZRAM_MAX_SLOTS
    iend
.name_str: db "ZRAM Compressed Swap Device", 0


section .bss

; Slot Allocation Metadata
zram_in_use:  resb ZRAM_MAX_SLOTS
align 2
zram_sizes:   resw ZRAM_MAX_SLOTS
align 8
zram_frames:  resq ZRAM_MAX_FRAMES

; Scratch buffer for compression
align 16
zram_scratch: resb ZRAM_SLOT_SIZE

%endif ; LIB_MEM_VIRT_ZRAM_ASM
