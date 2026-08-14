; =============================================================================
; Tattva OS — storage/uxfs/drivers/virtio_blk.asm
; =============================================================================
; VirtIO Block Device Driver (split virtqueue).
;
; Implements:
;   - Virtqueue initialisation and free-list setup (`uxfs_virtio_blk_init`)
;   - Three-descriptor request chaining (`uxfs_virtio_blk_submit`)
;   - Read, write and flush entry points (`uxfs_virtio_blk_read/write/flush`)
;   - Used-ring completion reaping (`uxfs_virtio_blk_poll`)
;
; A VirtIO block request is always a chain of THREE descriptors, never one:
;
;   [0] request header  (type + sector)   device reads
;   [1] data buffer                       device reads on write, writes on read
;   [2] status byte                       device writes
;
; They must be separate descriptors because each carries its own direction
; flag. Merging the header and data into one buffer is the classic mistake —
; the device would then have to write into memory the descriptor declared
; read-only, and a well-behaved device simply refuses.
;
; The split virtqueue has three parts: a descriptor table, an available ring
; the driver writes, and a used ring the device writes. Ownership transfers
; when the driver publishes an index; both sides need a memory barrier around
; that publication or the device can observe the index before the descriptors
; it points at.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define VIRTIO_BLK_T_IN             0           ; Read from device
%define VIRTIO_BLK_T_OUT            1           ; Write to device
%define VIRTIO_BLK_T_FLUSH          4           ; Flush device cache

%define VIRTIO_DESC_F_NEXT          1           ; Chain continues
%define VIRTIO_DESC_F_WRITE         2           ; Device writes into this buffer

%define VIRTIO_BLK_S_OK             0
%define VIRTIO_BLK_S_IOERR          1
%define VIRTIO_BLK_S_UNSUPP         2

%define VIRTIO_QUEUE_SIZE           128         ; Must be a power of two
%define VIRTIO_QUEUE_MASK           (VIRTIO_QUEUE_SIZE - 1)
%define VIRTIO_SECTOR_SIZE          512

struc uxfs_virtio_desc_t
    .addr:              resq 1      ; Physical buffer address
    .len:               resd 1      ; Buffer length
    .flags:             resw 1      ; NEXT / WRITE
    .next:              resw 1      ; Next descriptor index when NEXT is set
endstruc

struc uxfs_virtio_blk_req_t
    .type:              resd 1      ; VIRTIO_BLK_T_*
    .reserved:          resd 1
    .sector:            resq 1      ; 512-byte sector index, always 512 even
endstruc                            ; when the filesystem block is 4KB

; Available ring: flags, idx, then the ring entries.
struc uxfs_virtio_avail_t
    .flags:             resw 1
    .idx:               resw 1      ; Driver-owned producer index
    .ring:              resw VIRTIO_QUEUE_SIZE
endstruc

struc uxfs_virtio_used_elem_t
    .id:                resd 1      ; Head descriptor index of the chain
    .len:               resd 1      ; Bytes the device wrote
endstruc

struc uxfs_virtio_used_t
    .flags:             resw 1
    .idx:               resw 1      ; Device-owned producer index
    .reserved:          resd 1
    .ring:              resb VIRTIO_QUEUE_SIZE * uxfs_virtio_used_elem_t_size
endstruc

section .data
align 4096

global uxfs_virtio_desc_table
uxfs_virtio_desc_table:
    times VIRTIO_QUEUE_SIZE * uxfs_virtio_desc_t_size db 0

align 4096
uxfs_virtio_avail:      times uxfs_virtio_avail_t_size db 0

align 4096
uxfs_virtio_used:       times uxfs_virtio_used_t_size db 0

; Request headers and status bytes, one slot per descriptor triple.
align 64
uxfs_virtio_headers:    times (VIRTIO_QUEUE_SIZE / 3) * uxfs_virtio_blk_req_t_size db 0
uxfs_virtio_status:     times (VIRTIO_QUEUE_SIZE / 3) db 0

uxfs_virtio_free_head:  dw 0        ; Head of the free descriptor list
uxfs_virtio_last_used:  dw 0        ; Last used-ring index we reaped
uxfs_virtio_inflight:   dq 0
uxfs_virtio_completed:  dq 0
uxfs_virtio_errors:     dq 0

section .text

global uxfs_virtio_blk_init
global uxfs_virtio_blk_read
global uxfs_virtio_blk_write
global uxfs_virtio_blk_flush
global uxfs_virtio_blk_submit
global uxfs_virtio_blk_poll

; -----------------------------------------------------------------------------
; uxfs_virtio_blk_init
;
; Clears the rings and threads every descriptor onto the free list.
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
uxfs_virtio_blk_init:
    push rbx
    push r12

    lea rbx, [uxfs_virtio_desc_table]
    xor r12d, r12d

.vi_link:
    cmp r12d, VIRTIO_QUEUE_SIZE
    jae .vi_rings

    mov qword [rbx + uxfs_virtio_desc_t.addr], 0
    mov dword [rbx + uxfs_virtio_desc_t.len], 0
    mov word [rbx + uxfs_virtio_desc_t.flags], 0

    ; Each descriptor points at the next; the last wraps to 0.
    mov eax, r12d
    inc eax
    and eax, VIRTIO_QUEUE_MASK
    mov word [rbx + uxfs_virtio_desc_t.next], ax

    add rbx, uxfs_virtio_desc_t_size
    inc r12d
    jmp .vi_link

.vi_rings:
    mov word [uxfs_virtio_free_head], 0
    mov word [uxfs_virtio_last_used], 0

    lea rbx, [uxfs_virtio_avail]
    mov word [rbx + uxfs_virtio_avail_t.flags], 0
    mov word [rbx + uxfs_virtio_avail_t.idx], 0

    lea rbx, [uxfs_virtio_used]
    mov word [rbx + uxfs_virtio_used_t.flags], 0
    mov word [rbx + uxfs_virtio_used_t.idx], 0

    mov qword [uxfs_virtio_inflight], 0
    mov qword [uxfs_virtio_completed], 0
    mov qword [uxfs_virtio_errors], 0

    xor eax, eax
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_virtio_blk_submit
;
; Builds the three-descriptor chain and publishes it to the device.
;
; Inputs:
;   EDI = VIRTIO_BLK_T_* request type
;   RSI = Starting 512-byte sector
;   RDX = Physical data buffer (ignored for FLUSH)
;   ECX = Data length in bytes (0 for FLUSH)
;
; Returns:
;   EAX = Head descriptor index, or POSIX_ENOSPC when the ring is full
; -----------------------------------------------------------------------------
align 32
uxfs_virtio_blk_submit:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12d, edi                   ; Type
    mov r13, rsi                    ; Sector
    mov r14, rdx                    ; Data buffer
    mov r15d, ecx                   ; Data length

    ; Three descriptors are needed; refuse if fewer remain.
    mov rax, [uxfs_virtio_inflight]
    add rax, 3
    cmp rax, VIRTIO_QUEUE_SIZE
    ja .vs_full

    movzx ebx, word [uxfs_virtio_free_head]      ; Head index

    ; Slot index for the header/status arrays.
    mov eax, ebx
    xor edx, edx
    mov ecx, 3
    div ecx                                      ; EAX = slot
    mov r11d, eax

    ; ---- Descriptor 0: request header, device-readable ----
    mov rax, r11
    imul rax, uxfs_virtio_blk_req_t_size
    lea rcx, [uxfs_virtio_headers]
    add rcx, rax                                 ; Header address

    mov dword [rcx + uxfs_virtio_blk_req_t.type], r12d
    mov dword [rcx + uxfs_virtio_blk_req_t.reserved], 0
    mov [rcx + uxfs_virtio_blk_req_t.sector], r13

    mov rax, rbx
    imul rax, uxfs_virtio_desc_t_size
    lea rdx, [uxfs_virtio_desc_table]
    add rdx, rax                                 ; Descriptor 0

    mov [rdx + uxfs_virtio_desc_t.addr], rcx
    mov dword [rdx + uxfs_virtio_desc_t.len], uxfs_virtio_blk_req_t_size
    mov word [rdx + uxfs_virtio_desc_t.flags], VIRTIO_DESC_F_NEXT

    mov eax, ebx
    inc eax
    and eax, VIRTIO_QUEUE_MASK
    mov word [rdx + uxfs_virtio_desc_t.next], ax
    mov r10d, eax                                ; Descriptor 1 index

    ; ---- Descriptor 1: data buffer ----
    mov rax, r10
    imul rax, uxfs_virtio_desc_t_size
    lea rdx, [uxfs_virtio_desc_table]
    add rdx, rax

    mov [rdx + uxfs_virtio_desc_t.addr], r14
    mov dword [rdx + uxfs_virtio_desc_t.len], r15d

    ; A read means the DEVICE writes into this buffer.
    mov ax, VIRTIO_DESC_F_NEXT
    cmp r12d, VIRTIO_BLK_T_IN
    jne .vs_data_flags
    or ax, VIRTIO_DESC_F_WRITE

.vs_data_flags:
    mov word [rdx + uxfs_virtio_desc_t.flags], ax

    mov eax, r10d
    inc eax
    and eax, VIRTIO_QUEUE_MASK
    mov word [rdx + uxfs_virtio_desc_t.next], ax
    mov r9d, eax                                 ; Descriptor 2 index

    ; ---- Descriptor 2: status byte, device-writable, ends the chain ----
    lea rcx, [uxfs_virtio_status]
    add rcx, r11
    mov byte [rcx], 0xFF                         ; Poison: device overwrites it

    mov rax, r9
    imul rax, uxfs_virtio_desc_t_size
    lea rdx, [uxfs_virtio_desc_table]
    add rdx, rax

    mov [rdx + uxfs_virtio_desc_t.addr], rcx
    mov dword [rdx + uxfs_virtio_desc_t.len], 1
    mov word [rdx + uxfs_virtio_desc_t.flags], VIRTIO_DESC_F_WRITE
    mov word [rdx + uxfs_virtio_desc_t.next], 0

    ; Advance the free list past the three we consumed.
    mov eax, r9d
    inc eax
    and eax, VIRTIO_QUEUE_MASK
    mov word [uxfs_virtio_free_head], ax

    ; ---- Publish to the available ring ----
    lea rdx, [uxfs_virtio_avail]
    movzx eax, word [rdx + uxfs_virtio_avail_t.idx]
    mov ecx, eax
    and ecx, VIRTIO_QUEUE_MASK
    mov word [rdx + uxfs_virtio_avail_t.ring + rcx * 2], bx

    ; Descriptors must be visible before the index that exposes them.
    sfence

    inc ax
    mov word [rdx + uxfs_virtio_avail_t.idx], ax

    add qword [uxfs_virtio_inflight], 3

    mov eax, ebx                    ; Head index identifies this request
    jmp .vs_return

.vs_full:
    mov eax, POSIX_ENOSPC

.vs_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_virtio_blk_poll
;
; Reaps completions from the used ring and checks the status byte.
;
; Inputs:
;   RDI = Head descriptor index returned by submit
;
; Returns:
;   EAX = 0 on success
;         POSIX_EIO    when the device reported an error
;         POSIX_EBUSY  when the request has not completed yet
; -----------------------------------------------------------------------------
align 32
uxfs_virtio_blk_poll:
    push rbx
    push r12

    mov r12, rdi                    ; Head index

    lea rbx, [uxfs_virtio_used]
    movzx eax, word [rbx + uxfs_virtio_used_t.idx]
    movzx ecx, word [uxfs_virtio_last_used]
    cmp ax, cx
    je .vp_busy                     ; Device has not published anything new

    ; Device writes the ring before the index; order our reads to match.
    lfence

    mov word [uxfs_virtio_last_used], ax

    ; Status byte for this request's slot.
    mov rax, r12
    xor edx, edx
    mov ecx, 3
    div ecx                         ; EAX = slot

    lea rcx, [uxfs_virtio_status]
    movzx eax, byte [rcx + rax]

    sub qword [uxfs_virtio_inflight], 3
    inc qword [uxfs_virtio_completed]

    cmp eax, VIRTIO_BLK_S_OK
    jne .vp_ioerr

    xor eax, eax
    pop r12
    pop rbx
    ret

.vp_ioerr:
    inc qword [uxfs_virtio_errors]
    mov eax, POSIX_EIO
    pop r12
    pop rbx
    ret

.vp_busy:
    mov eax, POSIX_EBUSY
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_virtio_blk_read
;
; Inputs:
;   RDI = Starting 4KB block LBA
;   RSI = Physical destination buffer
;   RDX = Block count
;
; Returns:
;   EAX = Head descriptor index, or a negative POSIX error
; -----------------------------------------------------------------------------
align 32
uxfs_virtio_blk_read:
    push rbx

    ; VirtIO addresses 512-byte sectors regardless of filesystem block size.
    mov rbx, rdi
    shl rbx, 3                      ; 4096 / 512

    mov rcx, rdx
    shl rcx, 12                     ; Block count -> bytes

    mov edi, VIRTIO_BLK_T_IN
    mov rdx, rsi
    mov rsi, rbx
    call uxfs_virtio_blk_submit

    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_virtio_blk_write
;
; Inputs:
;   RDI = Starting 4KB block LBA
;   RSI = Physical source buffer
;   RDX = Block count
;
; Returns:
;   EAX = Head descriptor index, or a negative POSIX error
; -----------------------------------------------------------------------------
align 32
uxfs_virtio_blk_write:
    push rbx

    mov rbx, rdi
    shl rbx, 3

    mov rcx, rdx
    shl rcx, 12

    mov edi, VIRTIO_BLK_T_OUT
    mov rdx, rsi
    mov rsi, rbx
    call uxfs_virtio_blk_submit

    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_virtio_blk_flush
;
; Forces the device to commit its write cache. A journal must call this before
; treating a commit record as durable.
;
; Returns:
;   EAX = Head descriptor index, or a negative POSIX error
; -----------------------------------------------------------------------------
align 32
uxfs_virtio_blk_flush:
    mov edi, VIRTIO_BLK_T_FLUSH
    xor rsi, rsi                    ; FLUSH carries no sector
    xor rdx, rdx                    ; and no data buffer
    xor ecx, ecx
    jmp uxfs_virtio_blk_submit
