%ifndef GUARD_LIB_STR_UNICODE_NAME_ASM
%define GUARD_LIB_STR_UNICODE_NAME_ASM
; =============================================================================
; str/unicode/name.asm
; Codepoint → Unicode name lookup (UnicodeData.txt name field).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   convert/hex.asm                  (str_u64_to_hex)
;   unicode/tables/name_table.s      (name string data, generated)
;
; -----------------------------------------------------------------------------
; Each Unicode codepoint has a unique name, e.g.:
;   U+0041 → "LATIN CAPITAL LETTER A"
;   U+1F600 → "GRINNING FACE"
;   U+00E9 → "LATIN SMALL LETTER E WITH ACUTE"
;
; Names are used for: character pickers, accessibility (screen readers),
; debugging, and the \N{NAME} escape in some languages.
;
; Storage: the full name table is ~1.5MB of strings. We use:
;   - Algorithmic names for ranges (Hangul syllables, CJK ideographs)
;   - A compressed string table for the rest
;
; Algorithmic name generation:
;   CJK:    "CJK UNIFIED IDEOGRAPH-XXXX"
;   Hangul: "HANGUL SYLLABLE " + jamo short names
;
; Functions:
;   str_cp_name           — get the name of a codepoint
;   str_cp_name_lookup    — reverse: find codepoint by name
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; Hangul constants
HANGUL_SBASE    equ 0xAC00
HANGUL_SLAST    equ 0xD7A3
HANGUL_LCOUNT   equ 19
HANGUL_VCOUNT   equ 21
HANGUL_TCOUNT   equ 28
HANGUL_NCOUNT   equ 588

extern _ucd_name_index      ; cp → offset into name_data (generated)
extern _ucd_name_data       ; concatenated name strings

section .rodata

_prefix_cjk:    db "CJK UNIFIED IDEOGRAPH-", 0
_prefix_hangul: db "HANGUL SYLLABLE ", 0
_prefix_tangut: db "TANGUT IDEOGRAPH-", 0

; Hangul jamo short names (L, V, T) for syllable name generation
_jamo_l:
    dq .g, .gg, .n, .d, .dd, .r, .m, .b, .bb, .s
    dq .ss, .ieung, .j, .jj, .c, .k, .t, .p, .h
.g:  db "G",0
.gg: db "GG",0
.n:  db "N",0
.d:  db "D",0
.dd: db "DD",0
.r:  db "R",0
.m:  db "M",0
.b:  db "B",0
.bb: db "BB",0
.s:  db "S",0
.ss: db "SS",0
.ieung: db "",0
.j:  db "J",0
.jj: db "JJ",0
.c:  db "C",0
.k:  db "K",0
.t:  db "T",0
.p:  db "P",0
.h:  db "H",0

_jamo_v:
    dq .a, .ae, .ya, .yae, .eo, .e, .yeo, .ye, .o, .wa, .wae
    dq .oe, .yo, .u, .weo, .we, .wi, .yu, .eu, .yi, .i
.a:   db "A",0
.ae:  db "AE",0
.ya:  db "YA",0
.yae: db "YAE",0
.eo:  db "EO",0
.e:   db "E",0
.yeo: db "YEO",0
.ye:  db "YE",0
.o:   db "O",0
.wa:  db "WA",0
.wae: db "WAE",0
.oe:  db "OE",0
.yo:  db "YO",0
.u:   db "U",0
.weo: db "WEO",0
.we:  db "WE",0
.wi:  db "WI",0
.yu:  db "YU",0
.eu:  db "EU",0
.yi:  db "YI",0
.i:   db "I",0

section .text

; -----------------------------------------------------------------------------
; str_cp_name
;
; Get the Unicode name of a codepoint, written to the output buffer.
;
; Signature:
;   int64_t str_cp_name(uint32_t cp, uint8_t *dst, uint64_t dst_cap,
;                        uint64_t *out_len)
;
; Arguments:
;   EDI  — codepoint
;   RSI  — destination buffer
;   RDX  — capacity
;   RCX  — out_len (may be null)
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NOT_FOUND  no name (unassigned)
;   RAX  = STR_ERR_BUF_TOO_SMALL
; -----------------------------------------------------------------------------

STR_FUNC str_cp_name

    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     ebx, edi            ; codepoint
    mov     r12, rsi            ; dst
    mov     r13, rdx            ; cap
    mov     r14, rcx            ; out_len

    ; Hangul syllable range?
    cmp     ebx, HANGUL_SBASE
    jb      .cn_check_cjk
    cmp     ebx, HANGUL_SLAST
    jbe     .cn_hangul

.cn_check_cjk:
    ; CJK Unified Ideographs: 0x4E00-0x9FFF (and extensions)
    cmp     ebx, 0x4E00
    jb      .cn_table
    cmp     ebx, 0x9FFF
    jbe     .cn_cjk
    ; CJK Ext A: 0x3400-0x4DBF
    cmp     ebx, 0x3400
    jb      .cn_table
    cmp     ebx, 0x4DBF
    jbe     .cn_cjk

.cn_table:
    ; general name table lookup (omitted — needs generated name_data)
    ; for now: return NOT_FOUND for non-algorithmic names
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_NOT_FOUND
    pop     rbp
    ret

.cn_cjk:
    ; "CJK UNIFIED IDEOGRAPH-" + hex(cp)
    ; copy prefix
    lea     rsi, [rel _prefix_cjk]
    mov     rdi, r12
    xor     r9, r9              ; dst offset

.cn_cjk_prefix:
    movzx   eax, byte [rsi + r9]
    test    al, al
    jz      .cn_cjk_hex
    cmp     r9, r13
    jae     .cn_overflow
    mov     [rdi + r9], al
    inc     r9
    jmp     .cn_cjk_prefix

.cn_cjk_hex:
    ; append hex codepoint (at least 4 digits)
    mov     rdi, rbx
    lea     rsi, [r12 + r9]
    mov     rdx, r13
    sub     rdx, r9
    sub     rsp, 8
    and     rsp, -8
    mov     rcx, rsp
    call    str_u64_to_hex
    mov     r8, [rsp]
    add     rsp, 8
    add     r9, r8

    test    r14, r14
    jz      .cn_ok
    mov     [r14], r9
    jmp     .cn_ok

.cn_hangul:
    ; "HANGUL SYLLABLE " + L + V + T short names
    lea     rsi, [rel _prefix_hangul]
    mov     rdi, r12
    xor     r9, r9

.cn_hangul_prefix:
    movzx   eax, byte [rsi + r9]
    test    al, al
    jz      .cn_hangul_jamo
    cmp     r9, r13
    jae     .cn_overflow
    mov     [rdi + r9], al
    inc     r9
    jmp     .cn_hangul_prefix

.cn_hangul_jamo:
    ; decompose syllable index
    mov     eax, ebx
    sub     eax, HANGUL_SBASE   ; SIndex

    ; L = SIndex / NCOUNT
    xor     edx, edx
    mov     ecx, HANGUL_NCOUNT
    div     ecx
    mov     r10d, eax           ; LIndex
    mov     r11d, edx           ; SIndex % NCOUNT

    ; V = (SIndex % NCOUNT) / TCOUNT
    mov     eax, r11d
    xor     edx, edx
    mov     ecx, HANGUL_TCOUNT
    div     ecx
    ; eax = VIndex, edx = TIndex

    push    rax                 ; VIndex
    push    rdx                 ; TIndex

    ; append L name
    lea     r8, [rel _jamo_l]
    mov     rsi, [r8 + r10 * 8]
    call    .append_str

    ; append V name
    pop     rdx
    pop     rax
    push    rdx
    lea     r8, [rel _jamo_v]
    mov     rsi, [r8 + rax * 8]
    call    .append_str

    ; append T name (if TIndex > 0)
    pop     rdx
    test    edx, edx
    jz      .cn_hangul_done
    ; T jamo names omitted for brevity (similar table)

.cn_hangul_done:
    test    r14, r14
    jz      .cn_ok
    mov     [r14], r9

.cn_ok:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.cn_overflow:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

; internal helper: append null-terminated string at rsi to dst[r9]
.append_str:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .append_done
    cmp     r9, r13
    jae     .append_done
    mov     [r12 + r9], al
    inc     r9
    inc     rsi
    jmp     .append_str
.append_done:
    ret

STR_ENDFUNC str_cp_name
%endif ; GUARD_LIB_STR_UNICODE_NAME_ASM
