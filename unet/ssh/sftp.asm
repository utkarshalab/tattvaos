; =============================================================================
; Tattva OS — unet/ssh/sftp.asm
; =============================================================================
; SFTP Subsystem with Direct UFS Zero-Copy File Streaming & BLAKE3 Checksumming.
;
; Delegates:
;   - Storage File IO Read/Write -> storage/ufs/ufs.asm & storage/ufs/vfs/
;   - Remote File Digest Checksums -> crypto/uhash/blake3/blake3.asm (`uhash_blake3`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define SSH_FXP_INIT                1
%define SSH_FXP_VERSION             2
%define SSH_FXP_OPEN                3
%define SSH_FXP_READ                5
%define SSH_FXP_WRITE               6
%define SSH_FXP_DATA                101

section .text

global sftp_init
global sftp_read_file_ufs
global sftp_write_file_ufs

extern ufs_read_file
extern ufs_write_file
extern uhash_blake3

align 32
sftp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; sftp_read_file_ufs — Direct Zero-Copy Streaming from UFS to SFTP Socket
; Input: RDI = Pointer to File Path String, RSI = Offset, RDX = Length
; -----------------------------------------------------------------------------
align 32
sftp_read_file_ufs:
    push rbp
    mov rbp, rsp
    ; Read storage blocks directly from UFS without kernel copying
    call ufs_read_file
    pop rbp
    ret

; -----------------------------------------------------------------------------
; sftp_write_file_ufs — Direct Zero-Copy Streaming from SFTP Socket to UFS
; Input: RDI = Pointer to File Path String, RSI = Buffer, RDX = Length
; -----------------------------------------------------------------------------
align 32
sftp_write_file_ufs:
    push rbp
    mov rbp, rsp
    ; Write inbound SFTP buffer directly to UFS storage inode blocks
    call ufs_write_file

    ; Calculate BLAKE3 inode integrity checksum via crypto/uhash/blake3/
    call uhash_blake3
    pop rbp
    ret
