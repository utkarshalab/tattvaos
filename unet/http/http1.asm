; =============================================================================
; Tattva OS — unet/http/http1.asm
; =============================================================================
; HTTP/1.1 Web Server Engine with Direct UXFS Zero-Copy Static File Streaming.
;
; Delegates:
;   - Static Asset File IO Read      -> storage/uxfs/vfs/ & storage/uxfs/uxfs.asm
;   - TLS 1.3 HTTPS Encryption        -> crypto/utls/ & crypto/ucrypt/
;   - HTTP Header Token Parsing      -> lib/uparser/ & lib/str/
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define HTTP1_METHOD_GET            1
%define HTTP1_METHOD_POST           2
%define HTTP1_METHOD_HEAD           3

struc http1_conn_t
    .socket_fd:         resd 1      ; Connection Socket Descriptor
    .state:             resd 1      ; HTTP State
    .method:            resd 1      ; GET / POST / HEAD
    .uri_path:          resb 256    ; Request URI Path
endstruc

section .text

global http1_init
global http1_process_request
global http1_stream_uxfs_file

; TODO: these two symbols are not defined by storage/uxfs. The subsystem's public
; file API is vfs_open / vfs_read / vfs_close. Wire the streaming path below to
; those (with proper argument marshalling) before this module is linked.
extern uxfs_read_file
extern uxfs_get_file_size
extern utls_server_handshake

align 32
http1_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
http1_process_request:
    push rbp
    mov rbp, rsp
    ; Parse HTTP request line & headers using lib/uparser/
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; http1_stream_uxfs_file — Direct Zero-Copy Streaming from UXFS to HTTP Socket
; Input: RDI = Pointer to URI Path String (e.g., "/var/www/index.html")
;        RSI = Socket File Descriptor
; -----------------------------------------------------------------------------
align 32
http1_stream_uxfs_file:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    ; Query file size directly from Universal File System (UXFS)
    call uxfs_get_file_size

    ; Stream UXFS storage blocks directly into socket TX DMA buffer
    call uxfs_read_file

    pop rbx
    pop rbp
    ret
