; =============================================================================
; Utkarsha OS — lib/ufont/layout/bidi.asm
; =============================================================================
; The Unicode Bidirectional Algorithm (UAX #9, Unicode 17), as tools/bidi.py
; models it - checked against Unicode's BidiTest.txt and
; BidiCharacterTest.txt (tests/host/bidi_check.py).
;
;   ufont_bidi(arena, code points, count, direction, levels) -> eax the
;       paragraph level (-1: out of memory). direction: 0 left to right, 1
;       right to left, 2 from the text's first strong character (P2, P3).
;       levels: u8 per character, 255 for those X9 removes (embedding and
;       override controls, PDF, boundary neutrals). One paragraph, one line:
;       explicit embeddings, overrides and isolates (125 deep), the weak
;       types, bracket pairs, neutrals, implicit levels, and L1's
;       separators and trailing white space at the paragraph level.
;   ufont_bidi_reorder(levels, count, order) -> eax how many indices were
;       written: the characters (removed ones left out) left to right (L2).
; =============================================================================

%include "ufont.inc"

extern arena_alloc
extern ufl_ucd_bidi
extern ufl_ucd_brackets
extern ufl_ucd_brackets_count

; Bidi_Class (tools/ucd_table.py's BIDI_CLASSES order)
%define BC_L    0
%define BC_R    1
%define BC_AL   2
%define BC_EN   3
%define BC_ES   4
%define BC_ET   5
%define BC_AN   6
%define BC_CS   7
%define BC_NSM  8
%define BC_BN   9
%define BC_B    10
%define BC_S    11
%define BC_WS   12
%define BC_ON   13
%define BC_LRE  14
%define BC_LRO  15
%define BC_RLE  16
%define BC_RLO  17
%define BC_PDF  18
%define BC_LRI  19
%define BC_RLI  20
%define BC_FSI  21
%define BC_PDI  22

%define MAX_DEPTH 125

; the state (on the stack, rbx)
%define BD_N        0                   ; u32
%define BD_PARA     4                   ; u32
%define BD_ORIG     8                   ; u8 per character: its class
%define BD_T        16                  ; u8: its class as resolved
%define BD_BR       24                  ; u32: bracket pair id | 1 << 31 closing (0: none)
%define BD_LV       32                  ; u8: levels (the caller's)
%define BD_KEPT     40                  ; u32: the characters X9 keeps
%define BD_NKEPT    48                  ; u32
%define BD_POS      56                  ; u32: a kept character's place among them (-1)
%define BD_MATCH    64                  ; u32: an isolate initiator's matching PDI (-1)
%define BD_MPDI     72                  ; u8: 1 a matched PDI
%define BD_SEQ      80                  ; u32: the isolating run sequence
%define BD_NSEQ     88                  ; u32
%define BD_TMP      96                  ; u32 x 2n: stacks
%define BD_PAIRS    104                 ; u32 x 2n: bracket pairs (opening, closing place)
%define BD_NPAIRS   112                 ; u32
%define BD_ESTACK   120                 ; u32 x 128: level | override << 8 | isolate << 16
%define BD_USED     128                 ; u8 per kept place: its run is in a sequence
%define BD_SOS      136                 ; u32 0 L, 1 R
%define BD_EOS      140
%define BD_E        144                 ; the embedding direction
%define BD_LEVEL    148
%define BD_SIZE     160

section .text

; ----------------------------------------------------------------------------
; ufont_bidi — rdi = arena, rsi = code points (u32), edx = count, ecx =
;   direction, r8 = levels (u8 x count) -> eax paragraph level, -1
; ----------------------------------------------------------------------------
global ufont_bidi
ufont_bidi:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, BD_SIZE + 8
    mov rbx, rsp
    mov [rbx + BD_N], edx
    mov [rbx + BD_LV], r8
    mov r12, rsi                        ; code points
    mov r13d, ecx                       ; direction
    xor eax, eax
    test edx, edx
    jz .empty
    ; one block: n x (1 + 1 + 4 + 4 + 4 + 4 + 1 + 4 + 8 + 8 + 1) + the stack
    mov eax, edx
    imul rsi, rax, 40
    add rsi, 128 * 4 + 64
    call arena_alloc
    test rax, rax
    jz .nomem
    mov ecx, [rbx + BD_N]
    mov [rbx + BD_ESTACK], rax
    add rax, 128 * 4
    mov [rbx + BD_BR], rax
    lea rax, [rax + rcx * 4]
    mov [rbx + BD_KEPT], rax
    lea rax, [rax + rcx * 4]
    mov [rbx + BD_POS], rax
    lea rax, [rax + rcx * 4]
    mov [rbx + BD_MATCH], rax
    lea rax, [rax + rcx * 4]
    mov [rbx + BD_SEQ], rax
    lea rax, [rax + rcx * 4]
    mov [rbx + BD_TMP], rax
    lea rax, [rax + rcx * 8]
    mov [rbx + BD_PAIRS], rax
    lea rax, [rax + rcx * 8]
    mov [rbx + BD_ORIG], rax
    add rax, rcx
    mov [rbx + BD_T], rax
    add rax, rcx
    mov [rbx + BD_MPDI], rax
    add rax, rcx
    mov [rbx + BD_USED], rax
    ; classes and brackets
    xor ebp, ebp
.classes:
    cmp ebp, [rbx + BD_N]
    jae .classes_done
    mov edi, [r12 + rbp * 4]
    call ufl_ucd_bidi
    mov rcx, [rbx + BD_ORIG]
    mov [rcx + rbp], al
    mov rcx, [rbx + BD_T]
    mov [rcx + rbp], al
    mov edi, [r12 + rbp * 4]
    call bd_bracket
    mov rcx, [rbx + BD_BR]
    mov [rcx + rbp * 4], eax
    mov rcx, [rbx + BD_MPDI]
    mov byte [rcx + rbp], 0
    mov rcx, [rbx + BD_MATCH]
    mov dword [rcx + rbp * 4], -1
    mov rcx, [rbx + BD_POS]
    mov dword [rcx + rbp * 4], -1
    inc ebp
    jmp .classes
.classes_done:
    ; P2, P3: the paragraph level
    mov eax, r13d
    cmp eax, 2
    jne .para
    xor edi, edi
    mov esi, [rbx + BD_N]
    call bd_first_strong
    cmp eax, 1
    je .para
    xor eax, eax
.para:
    mov [rbx + BD_PARA], eax
    call bd_explicit
    call bd_runs
    call bd_implicit
    call bd_line
    mov eax, [rbx + BD_PARA]
    jmp .out
.nomem:
    mov eax, -1
    jmp .out
.empty:
    mov eax, ecx
    cmp eax, 1
    je .out
    xor eax, eax
.out:
    add rsp, BD_SIZE + 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; edi = code point -> eax its bracket entry (0: none)
bd_bracket:
    lea r8, [rel ufl_ucd_brackets]
    xor r9d, r9d
    mov r10d, [rel ufl_ucd_brackets_count]
.search:
    cmp r9d, r10d
    jae .none
    lea r11d, [r9 + r10]
    shr r11d, 1
    mov eax, r11d
    shl eax, 3
    cmp edi, [r8 + rax]
    je .found
    jb .lo
    lea r9d, [r11 + 1]
    jmp .search
.lo:
    mov r10d, r11d
    jmp .search
.found:
    mov eax, [r8 + rax + 4]
    ret
.none:
    xor eax, eax
    ret

; edi = an isolate initiator -> eax its matching PDI in the original
;   classes (n when none; a paragraph separator stops the search)
bd_matching_pdi:
    mov r8, [rbx + BD_ORIG]
    mov ecx, 1                          ; depth
    lea eax, [rdi + 1]
.scan:
    cmp eax, [rbx + BD_N]
    jae .none
    movzx edx, byte [r8 + rax]
    cmp edx, BC_LRI
    jb .other
    cmp edx, BC_FSI
    ja .pdi
    inc ecx
    jmp .next
.pdi:
    cmp edx, BC_PDI
    jne .next
    dec ecx
    jz .out
    jmp .next
.other:
    cmp edx, BC_B
    je .none
.next:
    inc eax
    jmp .scan
.none:
    mov eax, [rbx + BD_N]
.out:
    ret

; edi = start, esi = end -> eax 0 L, 1 R / AL, -1 none (P2: isolates
;   skipped, a paragraph separator stops it)
bd_first_strong:
    push r12
    push r13
    push r14
    mov r12d, edi
    mov r13d, esi
    mov r14, [rbx + BD_ORIG]
.scan:
    cmp r12d, r13d
    jae .none
    movzx eax, byte [r14 + r12]
    cmp eax, BC_L
    je .l
    cmp eax, BC_R
    je .r
    cmp eax, BC_AL
    je .r
    cmp eax, BC_B
    je .none
    cmp eax, BC_LRI
    jb .next
    cmp eax, BC_FSI
    ja .next
    mov edi, r12d
    call bd_matching_pdi
    mov r12d, eax
.next:
    inc r12d
    jmp .scan
.l:
    xor eax, eax
    jmp .out
.r:
    mov eax, 1
    jmp .out
.none:
    mov eax, -1
.out:
    pop r14
    pop r13
    pop r12
    ret

; ----------------------------------------------------------------------------
; bd_explicit: X1 - X8 - every character's level from the embeddings,
;   overrides and isolates around it (directional status stack)
; ----------------------------------------------------------------------------
bd_explicit:
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov r14, [rbx + BD_ESTACK]
    mov eax, [rbx + BD_PARA]
    mov [r14], eax
    xor r15d, r15d                      ; top
    xor r12d, r12d                      ; overflow isolates
    xor r13d, r13d                      ; overflow embeddings
    xor ebp, ebp                        ; i
    xor r11d, r11d                      ; valid isolates
.char:
    cmp ebp, [rbx + BD_N]
    jae .out
    mov rax, [rbx + BD_ORIG]
    movzx ecx, byte [rax + rbp]
    mov edx, [r14 + r15 * 4]            ; the top: level | override << 8 | isolate << 16
    mov rax, [rbx + BD_LV]
    mov [rax + rbp], dl                 ; the level by default
    cmp ecx, BC_LRE
    jb .plain
    cmp ecx, BC_RLO
    jbe .embed
    cmp ecx, BC_PDF
    je .pdf
    cmp ecx, BC_PDI
    je .pdi
    ; LRI, RLI, FSI
    call .override_class
    xor r8d, r8d                        ; right to left
    cmp ecx, BC_RLI
    je .iso_rtl
    cmp ecx, BC_LRI
    je .iso_new
    push r11
    push rdx
    mov edi, ebp
    call bd_matching_pdi
    mov esi, eax
    lea edi, [rbp + 1]
    call bd_first_strong
    pop rdx
    pop r11
    xor r8d, r8d
    cmp eax, 1
    jne .iso_new
.iso_rtl:
    mov r8d, 1
.iso_new:
    call .next_level                    ; -> eax
    cmp eax, MAX_DEPTH
    ja .iso_overflow
    test r12d, r12d
    jnz .iso_overflow
    test r13d, r13d
    jnz .iso_overflow
    inc r11d
    inc r15d
    or eax, 1 << 16
    mov [r14 + r15 * 4], eax
    jmp .next
.iso_overflow:
    inc r12d
    jmp .next
.embed:
    ; RLE, LRE, RLO, LRO
    xor r8d, r8d
    cmp ecx, BC_RLE
    jb .embed_level
    mov r8d, 1
.embed_level:
    call .next_level
    cmp eax, MAX_DEPTH
    ja .embed_overflow
    test r12d, r12d
    jnz .embed_overflow
    test r13d, r13d
    jnz .embed_overflow
    cmp ecx, BC_LRO
    je .ov_l
    cmp ecx, BC_RLO
    jne .push
    or eax, 2 << 8                      ; override R
    jmp .push
.ov_l:
    or eax, 1 << 8                      ; override L
.push:
    inc r15d
    mov [r14 + r15 * 4], eax
    jmp .next
.embed_overflow:
    test r12d, r12d
    jnz .next
    inc r13d
    jmp .next
.pdf:
    test r12d, r12d
    jnz .next
    test r13d, r13d
    jz .pdf_pop
    dec r13d
    jmp .next
.pdf_pop:
    test edx, 1 << 16
    jnz .next
    test r15d, r15d
    jz .next
    dec r15d
    jmp .next
.pdi:
    test r12d, r12d
    jz .pdi_valid
    dec r12d
    jmp .pdi_level
.pdi_valid:
    test r11d, r11d
    jz .pdi_level
    xor r13d, r13d
.pdi_pop:
    mov eax, [r14 + r15 * 4]
    dec r15d
    test eax, 1 << 16
    jz .pdi_pop
    dec r11d
.pdi_level:
    mov edx, [r14 + r15 * 4]
    mov rax, [rbx + BD_LV]
    mov [rax + rbp], dl
    call .override_class
    jmp .next
.plain:
    cmp ecx, BC_B
    jne .plain_level
    mov eax, [rbx + BD_PARA]
    mov rdx, [rbx + BD_LV]
    mov [rdx + rbp], al
    jmp .next
.plain_level:
    cmp ecx, BC_BN
    je .next
    call .override_class
.next:
    inc ebp
    jmp .char
.out:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    ret
; the top's override (edx) on character ebp's class
.override_class:
    mov eax, edx
    shr eax, 8
    and eax, 0xFF
    jz .no_override
    dec eax
    mov rdi, [rbx + BD_T]
    mov [rdi + rbp], al
.no_override:
    ret
; edx = the top, r8d = 1 right to left -> eax the next odd / even level
.next_level:
    movzx eax, dl
    test r8d, r8d
    jz .even
    inc eax
    or eax, 1
    ret
.even:
    add eax, 2
    and eax, ~1
    ret

; is class eax removed by X9 -> ZF clear when removed (eax kept)
%macro REMOVED 1
    cmp %1, BC_BN
    je %%yes
    cmp %1, BC_LRE
    jb %%no
    cmp %1, BC_PDF
    ja %%no
%%yes:
    or %1, %1                           ; (class codes are not 0 here: ZF clear)
    jmp %%end
%%no:
    cmp %1, %1                          ; ZF set
%%end:
%endmacro

; ----------------------------------------------------------------------------
; bd_runs: X9, X10 - the kept characters, their level runs joined through
;   matched isolates into isolating run sequences, each resolved
; ----------------------------------------------------------------------------
bd_runs:
    push r12
    push r13
    push r14
    push r15
    push rbp
    ; the kept characters and their places
    mov r12, [rbx + BD_ORIG]
    mov r13, [rbx + BD_KEPT]
    xor ebp, ebp
    xor r14d, r14d
.keep:
    cmp ebp, [rbx + BD_N]
    jae .kept
    movzx eax, byte [r12 + rbp]
    REMOVED eax
    jnz .keep_next
    mov [r13 + r14 * 4], ebp
    mov rax, [rbx + BD_POS]
    mov [rax + rbp * 4], r14d
    mov rax, [rbx + BD_USED]
    mov byte [rax + r14], 0
    inc r14d
.keep_next:
    inc ebp
    jmp .keep
.kept:
    mov [rbx + BD_NKEPT], r14d
    ; isolate initiators matched to PDIs (a paragraph separator clears them)
    mov r15, [rbx + BD_TMP]
    xor ecx, ecx                        ; stack depth
    xor edx, edx
.match:
    cmp edx, r14d
    jae .matched
    mov ebp, [r13 + rdx * 4]
    movzx eax, byte [r12 + rbp]
    cmp eax, BC_B
    je .match_clear
    cmp eax, BC_PDI
    je .match_pdi
    cmp eax, BC_LRI
    jb .match_next
    cmp eax, BC_FSI
    ja .match_next
    mov [r15 + rcx * 4], ebp
    inc ecx
    jmp .match_next
.match_pdi:
    test ecx, ecx
    jz .match_next
    dec ecx
    mov eax, [r15 + rcx * 4]
    mov r8, [rbx + BD_MATCH]
    mov [r8 + rax * 4], ebp
    mov r8, [rbx + BD_MPDI]
    mov byte [r8 + rbp], 1
    jmp .match_next
.match_clear:
    xor ecx, ecx
.match_next:
    inc edx
    jmp .match
.matched:
    ; each level run (in order) that does not continue an earlier sequence
    xor r15d, r15d                      ; kept place
.run:
    cmp r15d, [rbx + BD_NKEPT]
    jae .out
    mov rax, [rbx + BD_USED]
    cmp byte [rax + r15], 0
    jne .run_skip
    mov ebp, [r13 + r15 * 4]
    movzx eax, byte [r12 + rbp]
    cmp eax, BC_PDI
    jne .sequence
    mov rax, [rbx + BD_MPDI]
    cmp byte [rax + rbp], 0
    jne .run_skip
.sequence:
    mov dword [rbx + BD_NSEQ], 0
    mov edi, r15d
.seq_run:
    call bd_append_run                  ; edi = run start place -> eax its last character
    ; joined on through a matched isolate whose PDI starts a run
    movzx ecx, byte [r12 + rax]
    cmp ecx, BC_LRI
    jb .seq_done
    cmp ecx, BC_FSI
    ja .seq_done
    mov rcx, [rbx + BD_MATCH]
    mov ecx, [rcx + rax * 4]
    cmp ecx, -1
    je .seq_done
    mov rdx, [rbx + BD_POS]
    mov edi, [rdx + rcx * 4]
    call bd_run_start
    jnz .seq_done
    jmp .seq_run
.seq_done:
    call bd_sequence
.run_skip:
    ; past this run
    mov edi, r15d
    call bd_run_end
    mov r15d, eax
    jmp .run
.out:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; edi = kept place -> ZF set when a level run starts there
bd_run_start:
    test edi, edi
    jz .yes
    mov r8, [rbx + BD_KEPT]
    mov r9, [rbx + BD_LV]
    mov eax, [r8 + rdi * 4]
    movzx eax, byte [r9 + rax]
    mov ecx, [r8 + rdi * 4 - 4]
    movzx ecx, byte [r9 + rcx]
    cmp eax, ecx
    jne .yes
    or eax, 1                           ; ZF clear
    ret
.yes:
    xor eax, eax
    ret

; edi = run start place -> eax the place after its run
bd_run_end:
    mov r8, [rbx + BD_KEPT]
    mov r9, [rbx + BD_LV]
    mov eax, [r8 + rdi * 4]
    movzx ecx, byte [r9 + rax]
    lea eax, [rdi + 1]
.scan:
    cmp eax, [rbx + BD_NKEPT]
    jae .out
    mov edx, [r8 + rax * 4]
    cmp cl, [r9 + rdx]
    jne .out
    inc eax
    jmp .scan
.out:
    ret

; edi = run start place: its characters onto the sequence, the run marked
;   used -> eax its last character
bd_append_run:
    push r12
    mov r12d, edi
    mov rax, [rbx + BD_USED]
    mov byte [rax + rdi], 1
    call bd_run_end
    mov r8, [rbx + BD_KEPT]
    mov r9, [rbx + BD_SEQ]
    mov ecx, [rbx + BD_NSEQ]
.copy:
    cmp r12d, eax
    jae .done
    mov edx, [r8 + r12 * 4]
    mov [r9 + rcx * 4], edx
    inc ecx
    inc r12d
    jmp .copy
.done:
    mov [rbx + BD_NSEQ], ecx
    mov eax, [r9 + rcx * 4 - 4]
    pop r12
    ret

; ----------------------------------------------------------------------------
; bd_sequence: the isolating run sequence in BD_SEQ - sos and eos, then the
;   weak types, bracket pairs and neutrals (W1 - W7, N0 - N2)
; ----------------------------------------------------------------------------
; the class of sequence item %2 into %1 (BD_SEQ in r12, BD_T in r13)
%macro TY 2
    mov r10d, [r12 + (%2) * 4]
    movzx %1, byte [r13 + r10]
%endmacro
%macro SETTY 2
    mov r10d, [r12 + (%1) * 4]
    mov byte [r13 + r10], %2
%endmacro

bd_sequence:
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov r12, [rbx + BD_SEQ]
    mov r13, [rbx + BD_T]
    mov r14d, [rbx + BD_NSEQ]
    ; the level, sos (against the character before), eos (after; the
    ; paragraph level after an isolate initiator or at the end)
    mov r8, [rbx + BD_LV]
    mov r9, [rbx + BD_POS]
    mov r11, [rbx + BD_KEPT]
    mov eax, [r12]
    movzx ecx, byte [r8 + rax]
    mov [rbx + BD_LEVEL], ecx
    mov edx, ecx
    and edx, 1
    mov [rbx + BD_E], edx
    mov eax, [r9 + rax * 4]             ; the first's place
    mov edx, [rbx + BD_PARA]
    test eax, eax
    jz .prev
    mov edx, [r11 + rax * 4 - 4]
    movzx edx, byte [r8 + rdx]
.prev:
    cmp edx, ecx
    cmovb edx, ecx
    and edx, 1
    mov [rbx + BD_SOS], edx
    mov eax, [r12 + r14 * 4 - 4]        ; the last
    mov edx, [rbx + BD_PARA]
    mov r10, [rbx + BD_ORIG]
    movzx r10d, byte [r10 + rax]
    cmp r10d, BC_LRI
    jb .after
    cmp r10d, BC_FSI
    jbe .eos
.after:
    mov eax, [r9 + rax * 4]
    inc eax
    cmp eax, [rbx + BD_NKEPT]
    jae .eos
    mov edx, [r11 + rax * 4]
    movzx edx, byte [r8 + rdx]
.eos:
    cmp edx, ecx
    cmovb edx, ecx
    and edx, 1
    mov [rbx + BD_EOS], edx
    ; W1: NSM takes the type before it (ON after an isolate initiator or PDI)
    xor ebp, ebp
.w1:
    cmp ebp, r14d
    jae .w2
    TY eax, rbp
    cmp eax, BC_NSM
    jne .w1_next
    mov eax, [rbx + BD_SOS]
    test ebp, ebp
    jz .w1_set
    TY eax, rbp - 1
    cmp eax, BC_LRI
    jb .w1_set
    mov eax, BC_ON
.w1_set:
    SETTY rbp, al
.w1_next:
    inc ebp
    jmp .w1
.w2:
    ; W2: EN after AL -> AN; W3: AL -> R
    mov ecx, [rbx + BD_SOS]
    xor ebp, ebp
.w2_each:
    cmp ebp, r14d
    jae .w4
    TY eax, rbp
    cmp eax, BC_AL
    ja .w2_en
    mov ecx, eax                        ; L, R, AL
    cmp eax, BC_AL
    jne .w2_next
    SETTY rbp, BC_R
    jmp .w2_next
.w2_en:
    cmp eax, BC_EN
    jne .w2_next
    cmp ecx, BC_AL
    jne .w2_next
    SETTY rbp, BC_AN
.w2_next:
    inc ebp
    jmp .w2_each
.w4:
    ; W4: one separator between numbers
    mov ebp, 1
.w4_each:
    lea eax, [rbp + 1]
    cmp eax, r14d
    jae .w5
    TY eax, rbp
    TY ecx, rbp - 1
    TY edx, rbp + 1
    cmp eax, BC_ES
    jne .w4_cs
    cmp ecx, BC_EN
    jne .w4_next
    cmp edx, BC_EN
    jne .w4_next
    SETTY rbp, BC_EN
    jmp .w4_next
.w4_cs:
    cmp eax, BC_CS
    jne .w4_next
    cmp ecx, edx
    jne .w4_next
    cmp ecx, BC_EN
    je .w4_num
    cmp ecx, BC_AN
    jne .w4_next
.w4_num:
    SETTY rbp, cl
.w4_next:
    inc ebp
    jmp .w4_each
.w5:
    ; W5: terminators next to European numbers
    xor ebp, ebp
.w5_each:
    cmp ebp, r14d
    jae .w6
    TY eax, rbp
    cmp eax, BC_ET
    jne .w5_next
    mov r15d, ebp                       ; the run's end
.w5_end:
    cmp r15d, r14d
    jae .w5_have
    TY eax, r15
    cmp eax, BC_ET
    jne .w5_have
    inc r15d
    jmp .w5_end
.w5_have:
    xor edx, edx
    test ebp, ebp
    jz .w5_after
    TY eax, rbp - 1
    cmp eax, BC_EN
    sete dl
.w5_after:
    cmp r15d, r14d
    jae .w5_apply
    TY eax, r15
    cmp eax, BC_EN
    jne .w5_apply
    mov edx, 1
.w5_apply:
    test edx, edx
    jz .w5_skip
.w5_set:
    cmp ebp, r15d
    jae .w5_each
    SETTY rbp, BC_EN
    inc ebp
    jmp .w5_set
.w5_skip:
    mov ebp, r15d
    jmp .w5_each
.w5_next:
    inc ebp
    jmp .w5_each
.w6:
    ; W6: the remaining separators and terminators -> ON
    xor ebp, ebp
.w6_each:
    cmp ebp, r14d
    jae .w7
    TY eax, rbp
    cmp eax, BC_ES
    je .w6_on
    cmp eax, BC_ET
    je .w6_on
    cmp eax, BC_CS
    jne .w6_next
.w6_on:
    SETTY rbp, BC_ON
.w6_next:
    inc ebp
    jmp .w6_each
.w7:
    ; W7: EN after L -> L
    mov ecx, [rbx + BD_SOS]
    xor ebp, ebp
.w7_each:
    cmp ebp, r14d
    jae .n0
    TY eax, rbp
    cmp eax, BC_R
    ja .w7_en
    mov ecx, eax
    jmp .w7_next
.w7_en:
    cmp eax, BC_EN
    jne .w7_next
    test ecx, ecx
    jnz .w7_next
    SETTY rbp, BC_L
.w7_next:
    inc ebp
    jmp .w7_each
.n0:
    call bd_brackets
    ; N1, N2: neutrals between like strong types take theirs, else the
    ; embedding direction
    xor ebp, ebp
.n1:
    cmp ebp, r14d
    jae .out
    TY eax, rbp
    call bd_is_ni
    jnz .n1_next
    mov r15d, ebp                       ; start
.n1_end:
    inc ebp
    cmp ebp, r14d
    jae .n1_have
    TY eax, rbp
    call bd_is_ni
    jz .n1_end
.n1_have:
    mov ecx, [rbx + BD_SOS]
    test r15d, r15d
    jz .n1_before
    TY eax, r15 - 1
    call bd_strong
    mov ecx, eax
.n1_before:
    mov edx, [rbx + BD_EOS]
    cmp ebp, r14d
    jae .n1_after
    TY eax, rbp
    call bd_strong
    mov edx, eax
.n1_after:
    cmp ecx, edx
    je .n1_set
    mov ecx, [rbx + BD_E]
.n1_set:
    cmp r15d, ebp
    jae .n1
    SETTY r15, cl
    inc r15d
    jmp .n1_set
.n1_next:
    inc ebp
    jmp .n1
.out:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; eax = class -> ZF set when a neutral or isolate (N1's NI)
bd_is_ni:
    cmp eax, BC_B
    jb .no
    cmp eax, BC_ON
    jbe .yes
    cmp eax, BC_LRI
    jb .no
.yes:
    cmp eax, eax
    ret
.no:
    cmp eax, -1
    ret

; eax = class -> eax 0 L, 1 R (R, EN, AN), -1 not strong
bd_strong:
    test eax, eax
    jz .out
    cmp eax, BC_R
    je .r
    cmp eax, BC_EN
    je .r
    cmp eax, BC_AN
    je .r
    mov eax, -1
    ret
.r:
    mov eax, 1
.out:
    ret

; ----------------------------------------------------------------------------
; bd_brackets: N0 - bracket pairs in the sequence (r12 BD_SEQ, r13 BD_T,
;   r14d its length) take the embedding direction when it is inside them,
;   else the opposite one inside when the context before agrees; marks
;   after them follow
; ----------------------------------------------------------------------------
bd_brackets:
    push rbp
    push r15
    push rsi
    ; the pairs: openings stacked (63 deep), a closing matched to the
    ; nearest opening of its pair
    mov r15, [rbx + BD_TMP]
    mov r9, [rbx + BD_PAIRS]
    mov r11, [rbx + BD_BR]
    xor ecx, ecx                        ; stack
    xor esi, esi                        ; pairs
    xor ebp, ebp
.find:
    cmp ebp, r14d
    jae .found
    mov eax, [r12 + rbp * 4]
    mov edx, [r11 + rax * 4]
    test edx, edx
    jz .find_next
    cmp byte [r13 + rax], BC_ON
    jne .find_next
    test edx, edx
    js .closing
    cmp ecx, 63
    je .found
    mov [r15 + rcx * 8], edx
    mov [r15 + rcx * 8 + 4], ebp
    inc ecx
    jmp .find_next
.closing:
    and edx, 0x7FFFFFFF
    mov r8d, ecx
.close_search:
    test r8d, r8d
    jz .find_next
    dec r8d
    cmp [r15 + r8 * 8], edx
    jne .close_search
    mov eax, [r15 + r8 * 8 + 4]
    mov [r9 + rsi * 8], eax
    mov [r9 + rsi * 8 + 4], ebp
    inc esi
    mov ecx, r8d
.find_next:
    inc ebp
    jmp .find
.found:
    ; by opening place (insertion sort)
    mov ebp, 1
.sort:
    cmp ebp, esi
    jae .sorted
    mov rax, [r9 + rbp * 8]
    mov ecx, ebp
.sort_in:
    test ecx, ecx
    jz .sort_put
    cmp [r9 + rcx * 8 - 8], eax
    jbe .sort_put
    mov rdx, [r9 + rcx * 8 - 8]
    mov [r9 + rcx * 8], rdx
    dec ecx
    jmp .sort_in
.sort_put:
    mov [r9 + rcx * 8], rax
    inc ebp
    jmp .sort
.sorted:
    xor r15d, r15d                      ; pair
.pair:
    cmp r15d, esi
    jae .out
    mov r9, [rbx + BD_PAIRS]
    mov r8d, [r9 + r15 * 8]             ; opening
    mov r11d, [r9 + r15 * 8 + 4]        ; closing
    ; strong types inside: the embedding direction, else the other
    mov edx, -1                         ; found
    lea ebp, [r8 + 1]
.inside:
    cmp ebp, r11d
    jae .inside_done
    TY eax, rbp
    call bd_strong
    inc ebp
    cmp eax, -1
    je .inside
    mov edx, eax
    cmp eax, [rbx + BD_E]
    jne .inside
.inside_done:
    cmp edx, -1
    je .pair_next
    cmp edx, [rbx + BD_E]
    je .set
    ; the other direction inside: the context before decides
    mov edx, [rbx + BD_SOS]
    mov ebp, r8d
.before:
    test ebp, ebp
    jz .before_done
    dec ebp
    TY eax, rbp
    call bd_strong
    cmp eax, -1
    je .before
    mov edx, eax
.before_done:
    cmp edx, [rbx + BD_E]
    je .set
    ; (the context agrees with the inside: its direction)
.set:
    SETTY r8, dl
    SETTY r11, dl
    ; marks after either bracket follow it
    mov ebp, r8d
    call .marks
    mov ebp, r11d
    call .marks
.pair_next:
    inc r15d
    jmp .pair
.out:
    pop rsi
    pop r15
    pop rbp
    ret
.marks:
    inc ebp
    cmp ebp, r14d
    jae .marks_out
    mov eax, [r12 + rbp * 4]
    mov rcx, [rbx + BD_ORIG]
    cmp byte [rcx + rax], BC_NSM
    jne .marks_out
    mov [r13 + rax], dl
    jmp .marks
.marks_out:
    ret

; ----------------------------------------------------------------------------
; bd_implicit: I1, I2 - levels raised by the resolved types
; ----------------------------------------------------------------------------
bd_implicit:
    mov r8, [rbx + BD_KEPT]
    mov r9, [rbx + BD_T]
    mov r10, [rbx + BD_LV]
    xor ecx, ecx
.each:
    cmp ecx, [rbx + BD_NKEPT]
    jae .out
    mov eax, [r8 + rcx * 4]
    movzx edx, byte [r9 + rax]
    movzx r11d, byte [r10 + rax]
    test r11d, 1
    jnz .odd
    cmp edx, BC_R
    je .one
    cmp edx, BC_EN
    je .two
    cmp edx, BC_AN
    je .two
    jmp .next
.odd:
    cmp edx, BC_L
    je .one
    cmp edx, BC_EN
    je .one
    cmp edx, BC_AN
    jne .next
.one:
    inc byte [r10 + rax]
    jmp .next
.two:
    add byte [r10 + rax], 2
.next:
    inc ecx
    jmp .each
.out:
    ret

; ----------------------------------------------------------------------------
; bd_line: L1 - separators, and white space and isolates before them or at
;   the end, at the paragraph level; removed characters 255
; ----------------------------------------------------------------------------
bd_line:
    mov r8, [rbx + BD_ORIG]
    mov r9, [rbx + BD_LV]
    mov r10d, [rbx + BD_PARA]
    mov edx, 1                          ; trailing
    mov ecx, [rbx + BD_N]
.each:
    test ecx, ecx
    jz .removed
    dec ecx
    movzx eax, byte [r8 + rcx]
    cmp eax, BC_S
    je .sep
    cmp eax, BC_B
    je .sep
    cmp eax, BC_WS
    je .ws
    cmp eax, BC_LRI
    jae .ws
    REMOVED eax
    jnz .ws
    xor edx, edx
    jmp .each
.sep:
    mov [r9 + rcx], r10b
    mov edx, 1
    jmp .each
.ws:
    test edx, edx
    jz .each
    mov [r9 + rcx], r10b
    jmp .each
.removed:
    mov ecx, [rbx + BD_N]
.rm:
    test ecx, ecx
    jz .out
    dec ecx
    movzx eax, byte [r8 + rcx]
    REMOVED eax
    jz .rm
    mov byte [r9 + rcx], 255
    jmp .rm
.out:
    ret

; ----------------------------------------------------------------------------
; ufont_bidi_reorder — rdi = levels (u8, 255 left out), esi = count, rdx =
;   order (u32 x count) -> eax how many written: left to right, every run at
;   a level or above reversed from the highest level to the lowest odd one
; ----------------------------------------------------------------------------
global ufont_bidi_reorder
ufont_bidi_reorder:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rdx
    ; the kept indices; the highest level and the lowest odd one
    xor ecx, ecx
    xor r14d, r14d                      ; written
    xor r8d, r8d                        ; highest
    mov r9d, 256                        ; lowest odd
.kept:
    cmp ecx, esi
    jae .levels
    movzx eax, byte [r12 + rcx]
    cmp eax, 255
    je .kept_next
    mov [r13 + r14 * 4], ecx
    inc r14d
    cmp eax, r8d
    cmova r8d, eax
.kept_next:
    inc ecx
    jmp .kept
.levels:
    ; (lowest odd level)
    xor ecx, ecx
.odd:
    cmp ecx, r14d
    jae .reverse
    mov eax, [r13 + rcx * 4]
    movzx eax, byte [r12 + rax]
    test eax, 1
    jz .odd_next
    cmp eax, r9d
    cmovb r9d, eax
.odd_next:
    inc ecx
    jmp .odd
.reverse:
    cmp r9d, 256
    jne .level
    lea r9d, [r8 + 1]
.level:
    cmp r8d, r9d
    jl .out
    xor ecx, ecx
.scan:
    cmp ecx, r14d
    jae .level_next
    mov eax, [r13 + rcx * 4]
    movzx eax, byte [r12 + rax]
    cmp eax, r8d
    jb .scan_next
    mov r15d, ecx                       ; run start
.run:
    inc ecx
    cmp ecx, r14d
    jae .flip
    mov eax, [r13 + rcx * 4]
    movzx eax, byte [r12 + rax]
    cmp eax, r8d
    jae .run
.flip:
    lea r10d, [rcx - 1]
    mov r11d, r15d
.swap:
    cmp r11d, r10d
    jge .scan
    mov eax, [r13 + r11 * 4]
    mov edx, [r13 + r10 * 4]
    mov [r13 + r11 * 4], edx
    mov [r13 + r10 * 4], eax
    inc r11d
    dec r10d
    jmp .swap
.scan_next:
    inc ecx
    jmp .scan
.level_next:
    dec r8d
    jmp .level
.out:
    mov eax, r14d
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
