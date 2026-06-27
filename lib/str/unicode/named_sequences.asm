; =============================================================================
; str/unicode/named_sequences.asm
; Named character sequence lookup (NamedSequences.txt).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Source: NamedSequences.txt, NamedSequencesProv.txt
;
; -----------------------------------------------------------------------------
; Named sequences are defined by the Unicode Standard as named combinations
; of codepoints that represent a single entity. Unlike single codepoints,
; these require multiple codepoints to represent.
;
; Examples:
;   "LATIN SMALL LETTER DZ"                    → U+0064 U+007A
;   "TAMIL SYLLABLE KSSAI"                     → U+0B95 U+0BCD U+0BB7 U+0BC8
;   "KATAKANA LETTER AINU P"                   → U+31F7 U+309A
;   "MODIFIER LETTER EXTRA-LOW EXTRA-HIGH..."  → U+02E9 U+02E5
;
; This module provides lookup functionality for named sequences.
; The sequences are stored in a compact read-only table in .rodata.
;
; Functions:
;   str_named_sequence_lookup   — look up a named sequence by name
;   str_named_sequence_count    — total number of named sequences
;   str_named_sequence_by_index — get nth named sequence
;   str_named_sequence_name     — get name of nth sequence
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_cmp
extern str_eq

; Maximum codepoints in a named sequence (Unicode spec: typically 2-6)
MAX_SEQ_LEN     equ 8

section .text

; -----------------------------------------------------------------------------
; str_named_sequence_count
;
; Get the total number of named sequences in the database.
;
; Signature:
;   uint64_t str_named_sequence_count(void)
;
; Returns:
;   RAX  — number of named sequences
; -----------------------------------------------------------------------------

STR_FUNC str_named_sequence_count

    lea     rax, [rel _ns_count]
    mov     rax, [rax]
    pop     rbp
    ret

STR_ENDFUNC str_named_sequence_count

; -----------------------------------------------------------------------------
; str_named_sequence_lookup
;
; Look up a named sequence by name string.
; Returns the codepoint sequence in the caller's buffer.
;
; Signature:
;   int64_t str_named_sequence_lookup(const StrSlice *name,
;                                      uint32_t *out_cps, uint64_t cap,
;                                      uint64_t *out_count)
;
; Arguments:
;   RDI  — name of the sequence (StrSlice)
;   RSI  — output buffer for codepoints
;   RDX  — buffer capacity (uint32_t entries)
;   RCX  — pointer to receive count (may be NULL)
;
; Returns:
;   RAX  = STR_OK if found
;   RAX  = STR_ERR_NOT_FOUND if name not recognized
;   RAX  = STR_ERR_BUF_TOO_SMALL if buffer too small
; -----------------------------------------------------------------------------

STR_FUNC str_named_sequence_lookup

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     r12, rdi            ; name
    mov     r13, rsi            ; out buffer
    mov     r14, rdx            ; capacity
    mov     r15, rcx            ; out_count

    ; linear search through named sequences table
    ; (for OS kernel use, the table is small enough for linear scan;
    ;  a binary search on sorted names would be an optimization)

    lea     rbx, [rel _ns_entries]
    lea     rax, [rel _ns_count]
    mov     rcx, [rax]          ; total entries
    xor     r8, r8              ; index

.nsl_loop:
    cmp     r8, rcx
    jae     .nsl_not_found

    ; each entry: { name_ptr:8, name_len:8, seq_ptr:8, seq_len:8 }
    ; = 32 bytes per entry
    lea     rdi, [rbx + r8 * 8]
    ; construct StrSlice for this entry's name
    ; (name_ptr and name_len are at offset 0 and 8)

    ; compare names
    push    rcx
    push    r8
    mov     rdi, r12            ; caller's name
    lea     rsi, [rbx + r8 * 4 * 8] ; entry base (32 bytes per entry = 4*8)
    call    str_eq
    pop     r8
    pop     rcx

    test    eax, eax
    jnz     .nsl_found

    inc     r8
    jmp     .nsl_loop

.nsl_found:
    ; get sequence pointer and length
    lea     rax, [rbx + r8 * 4 * 8]
    mov     rsi, [rax + 16]     ; seq_ptr
    mov     rdx, [rax + 24]     ; seq_len (in codepoints)

    ; check buffer capacity
    cmp     r14, rdx
    jb      .nsl_buf_small

    ; copy codepoints
    xor     ecx, ecx
.nsl_copy:
    cmp     rcx, rdx
    jae     .nsl_copy_done
    mov     eax, [rsi + rcx * 4]
    mov     [r13 + rcx * 4], eax
    inc     rcx
    jmp     .nsl_copy

.nsl_copy_done:
    test    r15, r15
    jz      .nsl_ok
    mov     [r15], rdx

.nsl_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.nsl_not_found:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_NOT_FOUND
    pop     rbp
    ret

.nsl_buf_small:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_named_sequence_lookup

; -----------------------------------------------------------------------------
; str_named_sequence_by_index
;
; Get the nth named sequence's codepoints.
;
; Signature:
;   int64_t str_named_sequence_by_index(uint64_t index,
;                                        uint32_t *out_cps, uint64_t cap,
;                                        uint64_t *out_count)
;
; Arguments:
;   RDI  — sequence index (0-based)
;   RSI  — output buffer
;   RDX  — buffer capacity
;   RCX  — out_count (may be NULL)
;
; Returns:
;   RAX  = STR_OK on success
;   RAX  = STR_ERR_OUT_OF_BOUNDS if index >= count
; -----------------------------------------------------------------------------

STR_FUNC str_named_sequence_by_index

    guard_null rsi, STR_ERR_NULL

    ; check bounds
    lea     rax, [rel _ns_count]
    cmp     rdi, [rax]
    jae     .nsbi_oob

    push_regs rbx, r12

    mov     rbx, rdi            ; index
    mov     r12, rcx            ; out_count

    ; look up entry
    lea     rax, [rel _ns_entries]
    lea     rax, [rax + rbx * 4 * 8]  ; 32 bytes per entry

    mov     r8, [rax + 16]      ; seq_ptr
    mov     r9, [rax + 24]      ; seq_len

    ; check capacity
    cmp     rdx, r9
    jb      .nsbi_buf_small

    ; copy codepoints
    xor     ecx, ecx
.nsbi_copy:
    cmp     rcx, r9
    jae     .nsbi_done
    mov     eax, [r8 + rcx * 4]
    mov     [rsi + rcx * 4], eax
    inc     rcx
    jmp     .nsbi_copy

.nsbi_done:
    test    r12, r12
    jz      .nsbi_ok
    mov     [r12], r9

.nsbi_ok:
    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.nsbi_oob:
    mov     rax, STR_ERR_OUT_OF_BOUNDS
    pop     rbp
    ret

.nsbi_buf_small:
    pop_regs r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_named_sequence_by_index

; -----------------------------------------------------------------------------
; str_named_sequence_name
;
; Get the name of the nth named sequence.
;
; Signature:
;   int64_t str_named_sequence_name(uint64_t index, StrSlice *out)
;
; Arguments:
;   RDI  — sequence index (0-based)
;   RSI  — output StrSlice to fill with name pointer and length
;
; Returns:
;   RAX  = STR_OK on success
;   RAX  = STR_ERR_OUT_OF_BOUNDS if index >= count
; -----------------------------------------------------------------------------

STR_FUNC str_named_sequence_name

    guard_null rsi, STR_ERR_NULL

    ; check bounds
    lea     rax, [rel _ns_count]
    cmp     rdi, [rax]
    jae     .nsn_oob

    ; look up entry
    lea     rax, [rel _ns_entries]
    lea     rax, [rax + rdi * 4 * 8]

    ; copy name StrSlice fields to output
    mov     rcx, [rax]          ; name_ptr
    mov     [rsi + StrSlice.ptr], rcx
    mov     rcx, [rax + 8]      ; name_len
    mov     [rsi + StrSlice.len], rcx

    xor     eax, eax
    pop     rbp
    ret

.nsn_oob:
    mov     rax, STR_ERR_OUT_OF_BOUNDS
    pop     rbp
    ret

STR_ENDFUNC str_named_sequence_name

; =============================================================================
; Read-only data: Named sequences database
;
; Populated by the UCD build script from NamedSequences.txt.
; Stub data below; real data is generated into a separate linkable object.
; =============================================================================

section .rodata

_ns_count:
    dq      0                   ; filled by generated data

_ns_entries:
    ; Array of { name_ptr:8, name_len:8, seq_ptr:8, seq_len:8 }
    ; Populated by build scripts from NamedSequences.txt
    ; Each entry is 32 bytes.
    dq      0                   ; placeholder
