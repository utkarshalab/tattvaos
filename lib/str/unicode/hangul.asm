; =============================================================================
; str/unicode/hangul.asm
; Hangul syllable type classification and jamo utilities.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; Source: HangulSyllableType.txt, Jamo.txt
;
; -----------------------------------------------------------------------------
; Hangul syllable types (from HangulSyllableType.txt):
;   L   — Leading consonant jamo  (0x1100-0x1159)
;   V   — Vowel jamo              (0x1160-0x11A7)
;   T   — Trailing consonant jamo (0x11A8-0x11FF)
;   LV  — Syllable = L + V        (algorithmic: (cp-0xAC00) % 28 == 0)
;   LVT — Syllable = L + V + T    (algorithmic: (cp-0xAC00) % 28 != 0)
;   NA  — Not applicable
;
; This is used by grapheme.asm for Hangul grapheme cluster rules (GB6-GB8)
; and by normalize.asm for Hangul algorithmic decomposition/composition.
;
; Functions:
;   str_hangul_syllable_type  — classify codepoint as L/V/T/LV/LVT/NA
;   str_hangul_is_syllable    — is codepoint a precomposed syllable?
;   str_hangul_decompose      — decompose syllable to L+V(+T) jamo
;   str_hangul_compose        — compose L+V(+T) jamo to syllable
;   str_hangul_jamo_name      — get short jamo name (e.g. "G", "AE")
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; Hangul constants
HANGUL_SBASE    equ 0xAC00
HANGUL_LBASE    equ 0x1100
HANGUL_VBASE    equ 0x1161
HANGUL_TBASE    equ 0x11A7
HANGUL_LCOUNT   equ 19
HANGUL_VCOUNT   equ 21
HANGUL_TCOUNT   equ 28
HANGUL_NCOUNT   equ 588        ; VCOUNT * TCOUNT
HANGUL_SCOUNT   equ 11172      ; LCOUNT * NCOUNT
HANGUL_SLAST    equ 0xD7A3

; Syllable type enum
HST_NA  equ 0
HST_L   equ 1
HST_V   equ 2
HST_T   equ 3
HST_LV  equ 4
HST_LVT equ 5

section .text

; -----------------------------------------------------------------------------
; str_hangul_syllable_type
; Arguments: EDI = codepoint
; Returns:   AL = HST_* value
; -----------------------------------------------------------------------------

STR_FUNC str_hangul_syllable_type

    ; Leading consonant jamo: 0x1100-0x115F
    cmp     edi, 0x1100
    jb      .hst_chk_v
    cmp     edi, 0x115F
    jbe     .hst_l

.hst_chk_v:
    ; Vowel jamo: 0x1160-0x11A7
    cmp     edi, 0x1160
    jb      .hst_chk_t
    cmp     edi, 0x11A7
    jbe     .hst_v

.hst_chk_t:
    ; Trailing consonant jamo: 0x11A8-0x11FF
    cmp     edi, 0x11A8
    jb      .hst_chk_syllable
    cmp     edi, 0x11FF
    jbe     .hst_t

.hst_chk_syllable:
    ; Precomposed syllable: 0xAC00-0xD7A3
    cmp     edi, HANGUL_SBASE
    jb      .hst_chk_compat_l
    cmp     edi, HANGUL_SLAST
    ja      .hst_chk_compat_l

    ; LV vs LVT: (cp - SBASE) % TCOUNT == 0 → LV, else LVT
    mov     eax, edi
    sub     eax, HANGUL_SBASE
    xor     edx, edx
    mov     ecx, HANGUL_TCOUNT
    div     ecx
    test    edx, edx
    jz      .hst_lv
    jmp     .hst_lvt

.hst_chk_compat_l:
    ; Hangul Compatibility Jamo: 0x3131-0x314E (L), 0x314F-0x3163 (V)
    cmp     edi, 0x3131
    jb      .hst_chk_halfwidth
    cmp     edi, 0x314E
    jbe     .hst_l
    cmp     edi, 0x3163
    jbe     .hst_v

.hst_chk_halfwidth:
    ; Halfwidth Jamo: 0xFFA0-0xFFDC
    cmp     edi, 0xFFA1
    jb      .hst_na
    cmp     edi, 0xFFBE
    jbe     .hst_l
    cmp     edi, 0xFFC7
    jbe     .hst_v

.hst_na:  mov al, HST_NA
    pop rbp
    ret
.hst_l:   mov al, HST_L
    pop rbp
    ret
.hst_v:   mov al, HST_V
    pop rbp
    ret
.hst_t:   mov al, HST_T
    pop rbp
    ret
.hst_lv:  mov al, HST_LV
    pop rbp
    ret
.hst_lvt: mov al, HST_LVT
    pop rbp
    ret

STR_ENDFUNC str_hangul_syllable_type

; -----------------------------------------------------------------------------
; str_hangul_is_syllable — is it a precomposed Hangul syllable?
; -----------------------------------------------------------------------------

STR_FUNC str_hangul_is_syllable

    cmp     edi, HANGUL_SBASE
    jb      .his_no
    cmp     edi, HANGUL_SLAST
    ja      .his_no
    mov     eax, 1
    pop     rbp
    ret
.his_no:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_hangul_is_syllable

; -----------------------------------------------------------------------------
; str_hangul_decompose
;
; Decompose a precomposed syllable into L + V (+ T) jamo codepoints.
;
; Arguments:
;   EDI = syllable codepoint (must be in 0xAC00-0xD7A3)
;   RSI = output buffer (uint32[3])
; Returns:
;   EAX = number of jamo (2 for LV, 3 for LVT), 0 if not a syllable
; -----------------------------------------------------------------------------

STR_FUNC str_hangul_decompose

    guard_null rsi, STR_ERR_NULL

    cmp     edi, HANGUL_SBASE
    jb      .hd_not
    cmp     edi, HANGUL_SLAST
    ja      .hd_not

    mov     eax, edi
    sub     eax, HANGUL_SBASE   ; SIndex

    ; L = LBASE + SIndex / NCOUNT
    xor     edx, edx
    mov     ecx, HANGUL_NCOUNT
    div     ecx                 ; eax = SIndex/NCOUNT, edx = remainder
    add     eax, HANGUL_LBASE
    mov     [rsi], eax          ; L jamo

    ; V = VBASE + (remainder / TCOUNT)
    mov     eax, edx            ; remainder
    xor     edx, edx
    mov     ecx, HANGUL_TCOUNT
    div     ecx                 ; eax = .../TCOUNT, edx = TIndex
    add     eax, HANGUL_VBASE
    mov     [rsi + 4], eax      ; V jamo

    ; T (if TIndex > 0)
    test    edx, edx
    jz      .hd_lv

    add     edx, HANGUL_TBASE
    mov     [rsi + 8], edx      ; T jamo
    mov     eax, 3              ; LVT
    pop     rbp
    ret

.hd_lv:
    mov     eax, 2              ; LV
    pop     rbp
    ret

.hd_not:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_hangul_decompose

; -----------------------------------------------------------------------------
; str_hangul_compose
;
; Compose jamo into a precomposed syllable.
;
; Arguments: EDI = first (L or LV), ESI = second (V or T)
; Returns:   EAX = composed syllable, or 0 if not composable
; -----------------------------------------------------------------------------

STR_FUNC str_hangul_compose

    ; Case 1: L + V → LV
    mov     eax, edi
    sub     eax, HANGUL_LBASE
    cmp     eax, HANGUL_LCOUNT
    jae     .hc_try_lvt

    mov     ecx, esi
    sub     ecx, HANGUL_VBASE
    cmp     ecx, HANGUL_VCOUNT
    jae     .hc_fail

    imul    eax, HANGUL_VCOUNT
    add     eax, ecx
    imul    eax, HANGUL_TCOUNT
    add     eax, HANGUL_SBASE
    pop     rbp
    ret

.hc_try_lvt:
    ; Case 2: LV + T → LVT
    cmp     edi, HANGUL_SBASE
    jb      .hc_fail
    mov     eax, edi
    sub     eax, HANGUL_SBASE
    cmp     eax, HANGUL_SCOUNT
    jae     .hc_fail

    ; check LV (TIndex must be 0)
    xor     edx, edx
    mov     ecx, HANGUL_TCOUNT
    push    rax
    div     ecx
    pop     rax
    test    edx, edx
    jnz     .hc_fail

    ; check T
    mov     ecx, esi
    sub     ecx, HANGUL_TBASE
    cmp     ecx, 1
    jb      .hc_fail
    cmp     ecx, HANGUL_TCOUNT
    jae     .hc_fail

    ; LVT = LV + TIndex
    add     eax, HANGUL_SBASE
    add     eax, ecx
    pop     rbp
    ret

.hc_fail:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_hangul_compose