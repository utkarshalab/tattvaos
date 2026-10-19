; ============================================================================
; TrueType — Font Loading (offset table, table directory)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/font.inc"
%include "inc/canvas_client.inc"

; struct offsets (hoisted above use)
%define TtfFont_SIZE    112

section .text

; TtfFont struct layout (manual offsets to avoid NASM preprocessor issues)
; Offsets defined in inc/struct_offsets.inc

; ---------------------------------------------------------------------------
; ttf_probe
; ---------------------------------------------------------------------------
global ttf_probe
ttf_probe:
    PROLOGUE
    ASSERT_PTR rdi
    cmp rsi, 12
    jb .no
    mov eax, [rdi]
    cmp eax, 0x00010000  ; version 1.0 LE bytes 00 01 00 00
    je .yes
    cmp eax, 0x4F54544F  ; 'OTTO'
    je .yes
    cmp eax, 0x66637474  ; 'ttcf'
    je .yes
.no:
    xor rax, rax
    leave
    ret
.yes:
    mov rax, 1
    leave
    ret

; ---------------------------------------------------------------------------
; ttf_open
;   IN: rdi = arena, rsi = data, rdx = len — OUT: rax = TtfFont*
; ---------------------------------------------------------------------------
global ttf_open
ttf_open:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, r12
    mov rsi, r13
    call ttf_probe
    test rax, rax
    jz .bad
    mov rdi, rbx
    mov rsi, TtfFont_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov [rbx + TtfFont.data], r12
    mov [rbx + TtfFont.size], r13
    movzx eax, word [r12 + 4]
    xchg al, ah
    mov [rbx + TtfFont.num_tables], eax
    cmp eax, 64
    ja .bad
    lea rax, [r12 + 12]
    mov [rbx + TtfFont.dir], rax
    mov qword [rbx + TtfFont.cmap], 0
    mov qword [rbx + TtfFont.glyf], 0
    mov qword [rbx + TtfFont.loca], 0
    mov qword [rbx + TtfFont.head], 0
    mov qword [rbx + TtfFont.hhea], 0
    mov qword [rbx + TtfFont.hmtx], 0
    mov qword [rbx + TtfFont.kern], 0
    mov qword [rbx + TtfFont.maxp], 0
    mov rdi, rbx
    call ttf_index_tables
    test rax, rax
    jnz .bad
    ; required tables
    cmp qword [rbx + TtfFont.cmap], 0
    je .bad
    cmp qword [rbx + TtfFont.glyf], 0
    je .bad
    cmp qword [rbx + TtfFont.loca], 0
    je .bad
    cmp qword [rbx + TtfFont.head], 0
    je .bad
    cmp qword [rbx + TtfFont.maxp], 0
    je .bad
    ; unitsPerEm + loca format + numGlyphs
    mov rax, [rbx + TtfFont.head]
    movzx edx, word [rax + 18]
    xchg dl, dh
    mov [rbx + TtfFont.units_per_em], edx
    movzx edx, word [rax + 50]
    xchg dl, dh
    mov [rbx + TtfFont.loca_format], edx
    mov rax, [rbx + TtfFont.maxp]
    movzx edx, word [rax + 4]
    xchg dl, dh
    mov [rbx + TtfFont.num_glyphs], edx
    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.bad:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; ttf_index_tables
; ---------------------------------------------------------------------------
global ttf_index_tables
ttf_index_tables:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + TtfFont.dir]
    mov r13d, [rbx + TtfFont.num_tables]
    mov r14, [rbx + TtfFont.data]
    mov r15, [rbx + TtfFont.size]
    xor ecx, ecx
.loop:
    cmp ecx, r13d
    jae .done
    mov eax, [r12 + 0]   ; tag
    mov edx, [r12 + 8]   ; offset BE
    bswap edx
    mov esi, [r12 + 12]  ; length BE
    bswap esi
    ; bounds check
    mov edi, edx
    add edi, esi
    jc .fail
    cmp rdi, r15
    ja .fail
    lea rdi, [r14 + rdx]
    cmp eax, TTAG_cmap
    je .is_cmap
    cmp eax, TTAG_glyf
    je .is_glyf
    cmp eax, TTAG_loca
    je .is_loca
    cmp eax, TTAG_head
    je .is_head
    cmp eax, TTAG_hhea
    je .is_hhea
    cmp eax, TTAG_hmtx
    je .is_hmtx
    cmp eax, TTAG_kern
    je .is_kern
    cmp eax, TTAG_maxp
    je .is_maxp
    jmp .next
.is_cmap:
    mov [rbx + TtfFont.cmap], rdi
    jmp .next
.is_glyf:
    mov [rbx + TtfFont.glyf], rdi
    jmp .next
.is_loca:
    mov [rbx + TtfFont.loca], rdi
    jmp .next
.is_head:
    mov [rbx + TtfFont.head], rdi
    jmp .next
.is_hhea:
    mov [rbx + TtfFont.hhea], rdi
    jmp .next
.is_hmtx:
    mov [rbx + TtfFont.hmtx], rdi
    jmp .next
.is_kern:
    mov [rbx + TtfFont.kern], rdi
    jmp .next
.is_maxp:
    mov [rbx + TtfFont.maxp], rdi
.next:
    add r12, 16
    inc ecx
    jmp .loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.fail:
    mov rax, -EINVAL
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .data
global ttf_version
ttf_version: dq 0x010000
