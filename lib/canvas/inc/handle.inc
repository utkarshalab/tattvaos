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
%define HandleTable_entries    0
%define HandleTable_capacity   8
%define HandleTable_mask       16
%define HandleTable_count      24
%define HandleTable_next_index 32
%define HandleTable_arena      40
%define HandleTable_SIZE       48

; External functions
extern handle_table_init
extern handle_create
extern handle_destroy
extern handle_resolve
extern handle_acquire
extern handle_release
extern handle_get_generation

%endif ; __HANDLE_INC__