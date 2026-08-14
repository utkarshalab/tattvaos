; =============================================================================
; Tattva OS — storage/uwal/uwal.inc
; =============================================================================
; Master Schema Header for UWAL (Unikernel Write-Ahead Log).
;
; Record layout, segment geometry and durability constants shared by every
; UWAL module.
;
; UWAL is a general-purpose durable log. It is deliberately SEPARATE from the
; filesystem metadata journal in storage/uxfs/journal: uxfs journals its own
; metadata through its own block layer, while UWAL serves udb and any other
; client needing durability. Layering a database log on top of a filesystem
; log causes double journaling — every commit written twice, two fsyncs for
; one guarantee — which is precisely what "no redundant block layers" in
; storage/README.md rules out.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef UWAL_INC
%define UWAL_INC

%define UWAL_MAGIC                   0x4C41575532303236  ; "UWAL2026"
%define UWAL_REC_MAGIC               0x5257            ; "WR" record sentinel
%define UWAL_VERSION                 1
%define UWAL_BLOCK_SIZE              4096
%define UWAL_SEGMENT_SIZE            (16 * 1024 * 1024) ; 16MB per segment
%define UWAL_MAX_SEGMENTS            64
%define UWAL_MAX_PAYLOAD             (1024 * 1024)      ; 1MB per record
%define UWAL_HEADER_SIZE             64
%define UWAL_REC_HEADER_SIZE         48

; -----------------------------------------------------------------------------
; Record Types
; -----------------------------------------------------------------------------
%define UWAL_REC_INVALID             0
%define UWAL_REC_DATA                1     ; Client payload
%define UWAL_REC_COMMIT              2     ; Transaction commit marker
%define UWAL_REC_ABORT               3     ; Transaction rollback marker
%define UWAL_REC_CHECKPOINT          4     ; Replay may start here
%define UWAL_REC_SEGMENT_END         5     ; Segment boundary marker

; -----------------------------------------------------------------------------
; Streams — one physical log demultiplexes to several logical clients, so a
; replay handler only sees the records it owns.
; -----------------------------------------------------------------------------
%define UWAL_STREAM_UDB              1
%define UWAL_STREAM_UOBJECT          2
%define UWAL_STREAM_USER             16    ; First id available to callers

; -----------------------------------------------------------------------------
; Durability Modes — the trade between throughput and how much a crash costs.
; -----------------------------------------------------------------------------
%define UWAL_SYNC_NONE               0     ; Buffered; a crash loses recent records
%define UWAL_SYNC_FLUSH              1     ; Push to the device write cache
%define UWAL_SYNC_FUA                2     ; Force Unit Access: bypass the cache
%define UWAL_SYNC_BARRIER            3     ; Flush plus ordering barrier

; -----------------------------------------------------------------------------
; Result Codes — negative errno, matching uxfs convention.
; -----------------------------------------------------------------------------
%define UWAL_OK                      0
%define UWAL_ERR_IO                 -5
%define UWAL_ERR_NOMEM              -12
%define UWAL_ERR_BUSY               -16
%define UWAL_ERR_INVAL              -22
%define UWAL_ERR_NOSPC              -28
%define UWAL_ERR_CORRUPT            -74    ; EBADMSG: checksum or magic failure
%define UWAL_ERR_TORN               -75    ; EOVERFLOW: truncated tail record

; -----------------------------------------------------------------------------
; Log Superblock (64 bytes) — written at the head of the log region.
; -----------------------------------------------------------------------------
struc uwal_super_t
    .magic:             resq 1      ; UWAL_MAGIC
    .version:           resd 1      ; UWAL_VERSION
    .block_size:        resd 1      ; UWAL_BLOCK_SIZE
    .segment_size:      resq 1      ; Bytes per segment
    .segment_count:     resd 1      ; Segments in the ring
    .sync_mode:         resd 1      ; UWAL_SYNC_*
    .head_lsn:          resq 1      ; Next LSN to be assigned
    .checkpoint_lsn:    resq 1      ; Replay may safely start here
    .base_lba:          resq 1      ; First block of the log region
    .checksum:          resd 1      ; CRC32C over the preceding fields
    .reserved:          resd 1
endstruc

; -----------------------------------------------------------------------------
; Record Header (48 bytes).
;
; `checksum` covers the header with the field zeroed plus the payload, so a
; torn write is detected rather than replayed. `prev_lsn` chains records so
; recovery can tell a genuine tail from a stale record left by a wrapped
; segment that happens to carry a valid checksum.
; -----------------------------------------------------------------------------
struc uwal_rec_t
    .magic:             resw 1      ; UWAL_REC_MAGIC
    .type:              resb 1      ; UWAL_REC_*
    .stream:            resb 1      ; Owning client
    .payload_len:       resd 1      ; Payload bytes following this header
    .lsn:               resq 1      ; Log sequence number, strictly increasing
    .prev_lsn:          resq 1      ; LSN of the preceding record
    .txn_id:            resq 1      ; Transaction this record belongs to
    .timestamp:         resq 1      ; TSC at append time
    .checksum:          resd 1      ; CRC32C over header (zeroed) + payload
    .reserved:          resd 1
endstruc

; -----------------------------------------------------------------------------
; Segment Descriptor — in-memory ring bookkeeping.
; -----------------------------------------------------------------------------
struc uwal_segment_t
    .base_lba:          resq 1      ; First block of this segment
    .write_offset:      resq 1      ; Bytes consumed so far
    .first_lsn:         resq 1      ; LSN of the first record here
    .last_lsn:          resq 1      ; LSN of the most recent record
    .state:             resd 1      ; UWAL_SEG_*
    .reserved:          resd 1
endstruc

%define UWAL_SEG_FREE                0
%define UWAL_SEG_ACTIVE              1     ; Currently being appended to
%define UWAL_SEG_SEALED              2     ; Full; still needed for recovery
%define UWAL_SEG_RECLAIMABLE         3     ; Checkpointed; may be reused

%endif ; UWAL_INC
