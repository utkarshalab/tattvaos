; ============================================================================
; TTF Tables — BE Readers + Table Lookup Helpers
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/font.inc"

section .text

; ---------------------------------------------------------------------------
; ttf_u16 — BE u16 at ptr
; ---------------------------------------------------------------------------
global ttf_u16
ttf_u16:
    PROLOGUE
    ASSERT_PTR rdi
    movzx eax, word [rdi]
    xchg al, ah
    leave
    ret

; ---------------------------------------------------------------------------
; ttf_u32 — BE u32 at ptr
; ---------------------------------------------------------------------------
global ttf_u32
ttf_u32:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi]
    bswap eax
    leave
    ret

; ---------------------------------------------------------------------------
; ttf_i16 — BE i16 at ptr (sign-extended)
; ---------------------------------------------------------------------------
global ttf_i16
ttf_i16:
    PROLOGUE
    ASSERT_PTR rdi
    movzx eax, word [rdi]
    xchg al, ah
    movsx eax, ax
    leave
    ret

; ---------------------------------------------------------------------------
; ttf_table_len
;   IN: rdi = font*, rsi = tag — OUT: rax = length, 0 if missing
; ---------------------------------------------------------------------------
global ttf_table_len
ttf_table_len:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx
    mov r13, [rbx + TtfFont.dir]
    mov ecx, [rbx + TtfFont.num_tables]
    xor r8d, r8d
.loop:
    cmp r8d, ecx
    jae .none
    mov eax, [r13 + 0]
    cmp eax, r12d
    je .found
    add r13, 16
    inc r8d
    jmp .loop
.found:
    mov eax, [r13 + 12]
    bswap eax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.none:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
global ttf_tables_version
ttf_tables_version: dq 0x010000
