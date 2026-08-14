; =============================================================================
; Tattva OS — storage/uxfs/cache/dedup.asm
; =============================================================================
; BLAKE3 Content-Addressed Storage Block Deduplication Engine.
;
; Uses Krapivin-Farach-Colton-Kuszmaul (2025) Tiny-Pointer Hash Tables to achieve
; O(1) constant-time deduplication lookup even when the table is 99.9% full!
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

section .text

global uxfs_dedup_init
global uxfs_dedup_query
global uxfs_dedup_insert

; extern uxfs_tiny_hash_init -> defined in storage/uxfs/cache/tinypointer_hash.asm (single-unit build: no extern needed)
; extern uxfs_tiny_hash_lookup -> defined in storage/uxfs/cache/tinypointer_hash.asm (single-unit build: no extern needed)
; extern uxfs_tiny_hash_insert -> defined in storage/uxfs/cache/tinypointer_hash.asm (single-unit build: no extern needed)
; extern uhash_blake3 -> defined in crypto/uhash/uhash.asm (single-unit build: no extern needed)

; -----------------------------------------------------------------------------
; uxfs_dedup_init
; -----------------------------------------------------------------------------
align 32
uxfs_dedup_init:
    call uxfs_tiny_hash_init
    ret

; -----------------------------------------------------------------------------
; uxfs_dedup_query
;
; Queries 4KB storage block for duplicate content using BLAKE3 tiny pointer hash.
;
; Inputs:
;   RDI = Pointer to 4KB storage block buffer
;
; Returns:
;   RAX = Physical block LBA of identical duplicate (or 0 if unique block)
; -----------------------------------------------------------------------------
align 32
uxfs_dedup_query:
    push rbx
    push r12

    mov rbx, rdi

    ; Compute BLAKE3 256-bit hash over 4KB block
    mov rdi, rbx
    mov rsi, 4096
    sub rsp, 32
    mov rdx, rsp
    call uhash_blake3

    ; Use first 64 bits of BLAKE3 hash for O(1) Tiny Pointer Hash lookup
    mov rdi, [rsp]
    add rsp, 32

    call uxfs_tiny_hash_lookup        ; Returns duplicate block LBA or 0

    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_dedup_insert
;
; Registers new unique 4KB block into Tiny Pointer hash table.
;
; Inputs:
;   RDI = Pointer to 4KB storage block buffer
;   RSI = Physical block LBA
; -----------------------------------------------------------------------------
align 32
uxfs_dedup_insert:
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi

    mov rdi, rbx
    mov rsi, 4096
    sub rsp, 32
    mov rdx, rsp
    call uhash_blake3

    mov rdi, [rsp]
    add rsp, 32

    mov rsi, r12
    call uxfs_tiny_hash_insert

    pop r13
    pop r12
    pop rbx
    ret
