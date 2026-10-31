; =============================================================================
; Utkarsha OS — lib/ufont/sfnt/woff.asm
; =============================================================================
; WOFF 1.0 fonts: unpacked into the font they wrap, which ufont_open then
; reads.
;
;   ufl_woff_unpack(arena, data, length) -> rax = the sfnt's bytes (in the
;       arena), rdx = its length; rax 0: damaged, or out of memory
;
; The header (signature, flavor, table count) and the table directory are
; checked against the data; each table is copied, or when stored smaller
; than its length inflated from its zlib stream (the program provides
; inflate, RFC 1951, as Canvas does); its length must come out exactly.
; The tables go 4-byte aligned after a fresh table directory. Metadata and
; private data are not read.
; =============================================================================

%include "ufont.inc"

extern arena_alloc
extern inflate

%define WOFF_HEADER     44
%define WOFF_ENTRY      20
%define WOFF_MAX        (256 * 1024 * 1024)     ; the unpacked font at most

section .text

%macro BE32 2
    mov %1, %2
    bswap %1
%endmacro

; ----------------------------------------------------------------------------
; ufl_woff_unpack — rdi = arena, rsi = data, rdx = length
; ----------------------------------------------------------------------------
%define WU_ARENA    0
%define WU_DATA     8
%define WU_LEN      16
%define WU_OUT      24
%define WU_SIZE     32                  ; the font's size
%define WU_N        40                  ; u32 tables
%define WU_AT       48                  ; where the next table goes
%define WU_I        56                  ; u32
%define WU_FRAME    64

global ufl_woff_unpack
ufl_woff_unpack:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, WU_FRAME
    mov [rsp + WU_ARENA], rdi
    mov [rsp + WU_DATA], rsi
    mov [rsp + WU_LEN], rdx
    mov r12, rsi
    cmp rdx, WOFF_HEADER
    jb .bad
    cmp dword [r12], 'wOFF'
    jne .bad
    movzx eax, word [r12 + 12]
    xchg al, ah                         ; tables
    test eax, eax
    jz .bad
    mov [rsp + WU_N], eax
    imul rcx, rax, WOFF_ENTRY
    add rcx, WOFF_HEADER
    cmp rcx, rdx
    ja .bad
    ; the size: the directory, then every table 4-byte aligned
    mov eax, [rsp + WU_N]
    shl rax, 4
    add rax, 12
    mov r13, rax
    lea r14, [r12 + WOFF_HEADER]
    mov ecx, [rsp + WU_N]
.size:
    test ecx, ecx
    jz .sized
    BE32 edx, [r14 + 12]                ; origLength
    add rdx, 3
    and rdx, -4
    add r13, rdx
    cmp r13, WOFF_MAX
    ja .bad
    add r14, WOFF_ENTRY
    dec ecx
    jmp .size
.sized:
    mov [rsp + WU_SIZE], r13
    mov rdi, [rsp + WU_ARENA]
    mov rsi, r13
    call arena_alloc
    test rax, rax
    jz .bad
    mov [rsp + WU_OUT], rax
    mov rdi, rax
    mov rcx, r13
    xor eax, eax
    rep stosb                           ; padding zero
    ; the sfnt header: the flavor, the table count
    mov rbx, [rsp + WU_OUT]
    mov eax, [r12 + 4]
    mov [rbx], eax
    mov ax, [r12 + 12]
    mov [rbx + 4], ax
    mov eax, [rsp + WU_N]
    shl rax, 4
    add rax, 12
    mov [rsp + WU_AT], rax
    mov dword [rsp + WU_I], 0
.table:
    mov eax, [rsp + WU_I]
    cmp eax, [rsp + WU_N]
    jae .done
    imul r14, rax, WOFF_ENTRY
    add r14, r12
    add r14, WOFF_HEADER                ; the WOFF entry
    mov rbx, [rsp + WU_OUT]
    shl rax, 4
    lea r15, [rbx + rax + 12]           ; the sfnt entry
    mov eax, [r14]
    mov [r15], eax                      ; tag
    mov eax, [r14 + 16]
    mov [r15 + 4], eax                  ; checksum
    mov rax, [rsp + WU_AT]
    mov ecx, eax
    bswap ecx
    mov [r15 + 8], ecx                  ; offset
    mov eax, [r14 + 12]
    mov [r15 + 12], eax                 ; length
    ; its data in the WOFF file
    BE32 esi, [r14 + 4]                 ; offset
    BE32 edx, [r14 + 8]                 ; compLength
    BE32 r13d, [r14 + 12]               ; origLength
    lea rax, [rsi + rdx]
    cmp rax, [rsp + WU_LEN]
    ja .bad
    cmp edx, r13d
    ja .bad
    add rsi, r12
    mov rdi, [rsp + WU_AT]
    add rdi, rbx
    cmp edx, r13d
    jb .inflate
    mov ecx, edx                        ; stored as it is
    rep movsb
    jmp .placed
.inflate:
    ; a zlib stream: its 2-byte header, then deflate
    cmp edx, 6
    jb .bad
    movzx eax, byte [rsi]
    and eax, 0x0F
    cmp eax, 8                          ; deflate
    jne .bad
    test byte [rsi + 1], 0x20           ; no preset dictionary
    jnz .bad
    mov rcx, rdi                        ; out
    add rsi, 2
    sub edx, 2
    mov r8d, r13d                       ; its capacity: the length
    mov rdi, [rsp + WU_ARENA]
    call inflate
    cmp rax, r13
    jne .bad                            ; exactly the length
.placed:
    add r13, 3
    and r13, -4
    add [rsp + WU_AT], r13
    inc dword [rsp + WU_I]
    jmp .table
.done:
    mov rax, [rsp + WU_OUT]
    mov rdx, [rsp + WU_SIZE]
    jmp .out
.bad:
    xor eax, eax
    xor edx, edx
.out:
    add rsp, WU_FRAME
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
