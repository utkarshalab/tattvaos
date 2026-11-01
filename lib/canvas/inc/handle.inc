; ============================================================================
; Handle Table Interface — Generation-Tagged Handles (u32)
; 20-bit index, 12-bit generation = 1M objects, 4096 wraps
; ============================================================================

%ifndef __HANDLE_INC__
%define __HANDLE_INC__

; Handle encoding
%define HANDLE_INDEX_BITS    20
%define HANDLE_GEN_BITS      12
%define HANDLE_INDEX_MASK    ((1 << HANDLE_INDEX_BITS) - 1)
%define HANDLE_GEN_MASK      ((1 << HANDLE_GEN_BITS) - 1)
%define HANDLE_MAX_INDEX     (1 << HANDLE_INDEX_BITS)   ; 1,048,576
%define HANDLE_MAX_GEN       (1 << HANDLE_GEN_BITS)     ; 4,096

; HandleTable struct offsets
struc HandleTable
    .entries:                 resq 1
    .capacity:                resq 1
    .mask:                    resq 1
    .count:                   resq 1
    .next_index:              resq 1
    .arena:                   resq 1
endstruc

; External functions (src/core/handle.asm defines HANDLE_MODULE: it is their home)
%ifndef HANDLE_MODULE
extern handle_table_init
extern handle_create
extern handle_destroy
extern handle_resolve
extern handle_acquire
extern handle_release
extern handle_get_generation
%endif

%endif ; __HANDLE_INC__