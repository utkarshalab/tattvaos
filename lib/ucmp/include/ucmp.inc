; =============================================================================
; Tattva OS — lib/ucmp/include/ucmp.inc
; =============================================================================
; Master Compression Subsystem Definitions & Structures.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef UCMP_INC
%define UCMP_INC

; -----------------------------------------------------------------------------
; Error Codes
; -----------------------------------------------------------------------------
%define UCMP_OK                      0
%define UCMP_ERR_CORRUPT            -1
%define UCMP_ERR_NOMEM              -2
%define UCMP_ERR_BUFF_TOO_SMALL     -3
%define UCMP_ERR_UNSUPPORTED        -4
%define UCMP_ERR_INVALID_PARAM      -5
%define UCMP_ERR_CHECKSUM_MISMATCH  -6

; -----------------------------------------------------------------------------
; Compression Algorithm Identifiers
; -----------------------------------------------------------------------------
%define UCMP_ALGO_NONE               0
%define UCMP_ALGO_LZ4                1
%define UCMP_ALGO_ZSTD               2
%define UCMP_ALGO_DEFLATE            3
%define UCMP_ALGO_ZLIB               4
%define UCMP_ALGO_GZIP               5
%define UCMP_ALGO_SNAPPY             6
%define UCMP_ALGO_LZMA               7
%define UCMP_ALGO_XZ                 8
%define UCMP_ALGO_BROTLI             9
%define UCMP_ALGO_BZIP2              10
%define UCMP_ALGO_LZO                11

; -----------------------------------------------------------------------------
; Buffer & Window Sizes
; -----------------------------------------------------------------------------
%define UCMP_SLIDING_WINDOW_32K      32768
%define UCMP_SLIDING_WINDOW_64K      65536
%define UCMP_MAX_HUFFMAN_CODES       286
%define UCMP_LZ4_MIN_MATCH           4
%define UCMP_SNAPPY_MAX_OFFSET       65536

; -----------------------------------------------------------------------------
; Compression Stream State Structure
; -----------------------------------------------------------------------------
struc ucmp_stream_t
    .algo_id:           resd 1      ; UCMP_ALGO_LZ4, ZSTD, DEFLATE, etc.
    .flags:             resd 1      ; Stream configuration flags
    .src_ptr:           resq 1      ; Source uncompressed/compressed data buffer pointer
    .src_len:           resq 1      ; Source length in bytes
    .src_pos:           resq 1      ; Current source read offset
    .dst_ptr:           resq 1      ; Destination output buffer pointer
    .dst_len:           resq 1      ; Destination capacity in bytes
    .dst_written:       resq 1      ; Total bytes written to destination
    .checksum:          resd 1      ; Running CRC32 / Adler32 checksum
    .reserved:          resq 4      ; Reserved state expansion
endstruc

%endif ; UCMP_INC
