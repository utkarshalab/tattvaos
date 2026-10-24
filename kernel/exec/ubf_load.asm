; =============================================================================
; Utkarsha OS — kernel/exec/ubf_load.asm
; =============================================================================
; The program loader: a UBF file (docs/UBF_SPEC.md) in memory becomes a
; mapped, relocated program, then a fiber.
;
;   ubf_load   checks the whole file before touching memory (§9: header,
;              every table's bounds, the SHA-256, the CPU features, the
;              segments, every relocation, import and export), then
;              allocates pages, copies the segments, applies the
;              relocations, resolves the imports against the kernel's
;              exports, and maps each segment into the program window with
;              its final permissions: text R-X, rodata R--, data / bss RW-.
;   ubf_start  starts an application's or command's entry point as a fiber.
;
; The image is written through the identity mapping of its physical pages;
; the program runs at its window address, which is what the relocations and
; import slots are computed against. Pages are 4 KiB so each segment gets
; exactly its own permissions; nothing is ever writable and executable.
; =============================================================================

%ifndef KERNEL_EXEC_UBF_LOAD_ASM
%define KERNEL_EXEC_UBF_LOAD_ASM

%include "kernel/exec/ubf.inc"

; ubf_load's stack frame
%define LF_CTX          0                                   ; sha256_ctx_t
%define LF_DIGEST       ((sha256_ctx_t_size + 15) & ~15)    ; 32 bytes
%define LF_ZERO         (LF_DIGEST + 32)                    ; 32 zero bytes
%define LF_PAGES        (LF_ZERO + 32)                      ; qword
%define LF_SIZE         (LF_PAGES + 8)      ; 6 pushes + this: RSP 16-aligned

section .data
align 8
ubf_window_next:    dq UBF_WINDOW_BASE

section .rodata
; the protection each segment type must declare (index = type)
ubf_seg_prot:       db 0, UBF_PROT_R | UBF_PROT_X, UBF_PROT_R, UBF_PROT_R | UBF_PROT_W, UBF_PROT_R | UBF_PROT_W
align 8, db 0                       ; the ULF image stays a multiple of 8 bytes

section .text

; -----------------------------------------------------------------------------
; ubf_load — load a UBF program
; Input:  RDI = the file in memory, RSI = its length, RDX = ubf_prog_t* to fill
; Output: EAX = 0, or UBF_ERR_* (negative); on UBF_ERR_IMPORT the record's
;         .missing names the import that has no export
; The file must stay in memory while the program uses .exports / .strtab.
; -----------------------------------------------------------------------------
global ubf_load
ubf_load:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, LF_SIZE

    mov rbx, rdi                    ; RBX = the file
    mov r12, rsi                    ; R12 = its length
    mov r13, rdx                    ; R13 = the record
    xor r14d, r14d                  ; R14 = physical pages (0: none yet)

    mov rdi, r13
    xor eax, eax
    mov ecx, ubf_prog_t_size
    rep stosb

    ; ---- 1. the header ----
    cmp r12, UBF_HEADER_SIZE
    jb .format
    cmp dword [rbx + UBF_H_MAGIC], UBF_MAGIC
    jne .format
    cmp word [rbx + UBF_H_VERSION], UBF_VERSION
    jne .format
    cmp word [rbx + UBF_H_HSIZE], UBF_HEADER_SIZE
    jne .format
    cmp word [rbx + UBF_H_ARCH], UBF_ARCH_X86_64
    jne .format
    mov eax, [rbx + UBF_H_FILE_SIZE]
    cmp rax, r12
    jne .format
    movzx eax, word [rbx + UBF_H_KIND]
    cmp eax, UBF_KIND_APP
    jb .format
    cmp eax, UBF_KIND_CMD
    ja .format
    mov ecx, [rbx + UBF_H_FLAGS]
    test ecx, ~UBF_FLAG_ENTRY
    jnz .format                     ; an unknown flag
    ; an entry point exactly when the image is not a library
    cmp eax, UBF_KIND_LIB
    sete al
    xor al, 1                       ; AL = 1: must have an entry
    and cl, UBF_FLAG_ENTRY
    cmp al, cl
    jne .format
    mov rax, [rbx + UBF_H_MEM_SIZE]
    test rax, rax
    jz .format
    test eax, UBF_PAGE - 1
    jnz .format
    cmp rax, UBF_MAX_MEM
    ja .format
    mov rcx, [rbx + UBF_H_ENTRY]
    cmp rcx, rax
    jae .entry_checked_large
    jmp .entry_checked
.entry_checked_large:
    test byte [rbx + UBF_H_FLAGS], UBF_FLAG_ENTRY
    jnz .format                     ; an entry outside the image
.entry_checked:
    mov eax, [rbx + UBF_H_SEG_COUNT]
    test eax, eax
    jz .format
    cmp eax, UBF_MAX_SEGMENTS
    ja .format

    ; ---- 2. every table inside the file ----
    mov esi, [rbx + UBF_H_SEG_OFF]
    mov eax, [rbx + UBF_H_SEG_COUNT]
    shl rax, 5
    call .in_file
    jc .format
    mov esi, [rbx + UBF_H_REL_OFF]
    mov eax, [rbx + UBF_H_REL_COUNT]
    shl rax, 3
    call .in_file
    jc .format
    mov esi, [rbx + UBF_H_IMP_OFF]
    mov eax, [rbx + UBF_H_IMP_COUNT]
    shl rax, 4
    call .in_file
    jc .format
    mov esi, [rbx + UBF_H_EXP_OFF]
    mov eax, [rbx + UBF_H_EXP_COUNT]
    shl rax, 4
    call .in_file
    jc .format
    mov esi, [rbx + UBF_H_STR_OFF]
    mov eax, [rbx + UBF_H_STR_SIZE]
    call .in_file
    jc .format
    ; the string table ends in a NUL, so every name it holds terminates in it
    mov eax, [rbx + UBF_H_STR_SIZE]
    test eax, eax
    jz .strtab_ok
    mov ecx, [rbx + UBF_H_STR_OFF]
    add rcx, rax
    cmp byte [rbx + rcx - 1], 0
    jne .format
.strtab_ok:

    ; ---- 3. the SHA-256, of the file with its digest field zero ----
    lea rdi, [rsp + LF_ZERO]
    xor eax, eax
    mov ecx, 32
    rep stosb
    lea rdi, [rsp + LF_CTX]
    call sha256_init
    lea rdi, [rsp + LF_CTX]
    mov rsi, rbx
    mov edx, UBF_H_SHA256
    call sha256_update
    lea rdi, [rsp + LF_CTX]
    lea rsi, [rsp + LF_ZERO]
    mov edx, 32
    call sha256_update
    lea rdi, [rsp + LF_CTX]
    lea rsi, [rbx + UBF_H_SHA256 + 32]
    mov rdx, r12
    sub rdx, UBF_H_SHA256 + 32
    call sha256_update
    lea rdi, [rsp + LF_CTX]
    lea rsi, [rsp + LF_DIGEST]
    call sha256_final
    lea rsi, [rsp + LF_DIGEST]
    lea rdi, [rbx + UBF_H_SHA256]
    mov ecx, 32
    repe cmpsb
    jne .digest

    ; ---- 4. the CPU features it needs ----
    mov eax, [rbx + UBF_H_CPU]
    test eax, ~UBF_CPU_KNOWN
    jnz .format
    mov ebp, eax
    call ubf_cpu_features
    not eax
    test ebp, eax
    jnz .cpu

    ; ---- 5. the segments ----
    xor ebp, ebp                    ; EBP = the previous segment's end
    xor r15d, r15d                  ; R15 = the segment index
.seg_check:
    cmp r15d, [rbx + UBF_H_SEG_COUNT]
    jae .segs_ok
    call .seg_ptr                   ; RDI = the entry
    mov eax, [rdi + UBF_SEG_TYPE]
    cmp eax, UBF_SEG_TEXT
    jb .format
    cmp eax, UBF_SEG_BSS
    ja .format
    lea rcx, [rel ubf_seg_prot]
    movzx ecx, byte [rcx + rax]
    cmp ecx, [rdi + UBF_SEG_PROT]
    jne .format                     ; the wrong protection (never W|X)
    mov rcx, [rdi + UBF_SEG_MEM_OFF]
    test ecx, UBF_PAGE - 1
    jnz .format
    cmp rcx, rbp
    jb .format                      ; out of order or overlapping
    mov rdx, [rdi + UBF_SEG_MEM_SIZE]
    mov esi, [rdi + UBF_SEG_FILE_SIZE]
    cmp rsi, rdx
    ja .format
    add rcx, rdx
    jc .format
    cmp rcx, [rbx + UBF_H_MEM_SIZE]
    ja .format
    mov rbp, rcx
    cmp eax, UBF_SEG_BSS
    jne .seg_bytes
    test esi, esi
    jnz .format                     ; bss has no bytes in the file
    jmp .seg_next
.seg_bytes:
    mov eax, esi
    mov esi, [rdi + UBF_SEG_FILE_OFF]
    call .in_file
    jc .format
.seg_next:
    inc r15d
    jmp .seg_check
.segs_ok:

    ; ---- 6. each relocation patches 8 bytes some segment carries ----
    xor r15d, r15d
.rel_check:
    cmp r15d, [rbx + UBF_H_REL_COUNT]
    jae .rels_ok
    mov eax, [rbx + UBF_H_REL_OFF]
    lea rax, [rax + r15*8]
    cmp dword [rbx + rax + 4], UBF_REL_ABS64
    jne .format
    mov esi, [rbx + rax]
    mov edx, 0                      ; any segment with bytes
    call .in_segment
    jc .format
    inc r15d
    jmp .rel_check
.rels_ok:

    ; ---- 7. each import names a string and owns a rodata slot ----
    xor r15d, r15d
.imp_check:
    cmp r15d, [rbx + UBF_H_IMP_COUNT]
    jae .imps_ok
    call .imp_ptr                   ; RDI = the entry
    mov eax, [rdi + UBF_IMP_NAME]
    cmp eax, [rbx + UBF_H_STR_SIZE]
    jae .format
    test dword [rdi + UBF_IMP_FLAGS], ~UBF_IMP_WEAK
    jnz .format
    mov esi, [rdi + UBF_IMP_SLOT]
    mov edx, UBF_SEG_RODATA
    call .in_segment
    jc .format
    inc r15d
    jmp .imp_check
.imps_ok:

    ; ---- 8. each export names a string and a place in the image ----
    xor r15d, r15d
.exp_check:
    cmp r15d, [rbx + UBF_H_EXP_COUNT]
    jae .exps_ok
    mov eax, [rbx + UBF_H_EXP_OFF]
    mov ecx, r15d
    shl ecx, 4
    add rax, rcx
    mov ecx, [rbx + rax + UBF_EXP_NAME]
    cmp ecx, [rbx + UBF_H_STR_SIZE]
    jae .format
    mov rcx, [rbx + rax + UBF_EXP_OFFSET]
    cmp rcx, [rbx + UBF_H_MEM_SIZE]
    jae .format
    inc r15d
    jmp .exp_check
.exps_ok:

    ; ---- 9. pages, and a place in the program window ----
    mov rdi, [rbx + UBF_H_MEM_SIZE]
    shr rdi, 12
    mov [rsp + LF_PAGES], rdi
    call phys_alloc_pages
    test rax, rax
    jz .nomem
    mov r14, rax                    ; R14 = the physical pages
    mov rax, [rbx + UBF_H_MEM_SIZE]
    add rax, UBF_PAGE               ; an unmapped guard page after each image
    mov r15, rax
    lock xadd [rel ubf_window_next], r15    ; R15 = the virtual base
    add rax, r15
    mov rcx, UBF_WINDOW_LIMIT
    cmp rax, rcx
    ja .nomem_free

    ; zero it all (bss and the gaps), then copy each segment's bytes
    mov rdi, r14
    mov rcx, [rbx + UBF_H_MEM_SIZE]
    xor eax, eax
    rep stosb
    xor ebp, ebp
.copy:
    cmp ebp, [rbx + UBF_H_SEG_COUNT]
    jae .copied
    mov r8d, ebp
    call .seg_ptr_r8
    mov ecx, [rdi + UBF_SEG_FILE_SIZE]
    mov esi, [rdi + UBF_SEG_FILE_OFF]
    add rsi, rbx
    mov rax, [rdi + UBF_SEG_MEM_OFF]
    lea rdi, [r14 + rax]
    rep movsb
    inc ebp
    jmp .copy
.copied:

    ; ---- 10. relocations: each 64-bit field + the virtual base ----
    xor ebp, ebp
.reloc:
    cmp ebp, [rbx + UBF_H_REL_COUNT]
    jae .relocated
    mov eax, [rbx + UBF_H_REL_OFF]
    lea rax, [rax + rbp*8]
    mov eax, [rbx + rax]
    add [r14 + rax], r15
    inc ebp
    jmp .reloc
.relocated:

    ; ---- 11. imports: each slot gets the address its name resolves to ----
    xor ebp, ebp
.import:
    cmp ebp, [rbx + UBF_H_IMP_COUNT]
    jae .imported
    mov r8d, ebp
    call .imp_ptr_r8                ; RDI = the entry
    mov r9, rdi
    mov eax, [r9 + UBF_IMP_NAME]
    mov ecx, [rbx + UBF_H_STR_OFF]
    add rax, rcx
    lea rdi, [rbx + rax]            ; the name
    mov esi, [r9 + UBF_IMP_HASH]
    push r9
    push rdi
    call ubf_export_find
    pop rdi
    pop r9
    test rax, rax
    jnz .resolved
    test dword [r9 + UBF_IMP_FLAGS], UBF_IMP_WEAK
    jz .missing                     ; weak: the slot stays 0
.resolved:
    mov ecx, [r9 + UBF_IMP_SLOT]
    mov [r14 + rcx], rax
    inc ebp
    jmp .import
.missing:
    mov [r13 + ubf_prog_t.missing], rdi
    mov eax, UBF_ERR_IMPORT
    jmp .fail_free
.imported:

    ; ---- 12. map each segment's pages with its own permissions ----
    xor ebp, ebp
.map_seg:
    cmp ebp, [rbx + UBF_H_SEG_COUNT]
    jae .mapped
    mov r8d, ebp
    call .seg_ptr_r8
    mov eax, [rdi + UBF_SEG_TYPE]
    mov r12, PAGE_PRESENT                       ; text: R-X
    cmp eax, UBF_SEG_TEXT
    je .have_flags
    mov r12, PAGE_PRESENT | PAGE_NX             ; rodata: R--
    cmp eax, UBF_SEG_RODATA
    je .have_flags
    mov r12, PAGE_PRESENT | PAGE_WRITABLE | PAGE_NX ; data, bss: RW-
.have_flags:
    mov rcx, [rdi + UBF_SEG_MEM_OFF]            ; RCX = the first page
    mov rdx, [rdi + UBF_SEG_MEM_SIZE]
    lea rdx, [rcx + rdx + UBF_PAGE - 1]
    and rdx, -UBF_PAGE                          ; RDX = past the last page
.map_page:
    cmp rcx, rdx
    jae .seg_mapped
    push rcx
    push rdx
    lea rdi, [r15 + rcx]
    lea rsi, [r14 + rcx]
    mov rdx, r12
    call virt_map
    pop rdx
    pop rcx
    test eax, eax
    jz .map_failed
    add rcx, UBF_PAGE
    jmp .map_page
.seg_mapped:
    inc ebp
    jmp .map_seg
.map_failed:
    ; TODO: unmap the pages already mapped; until then they stay mapped (to
    ; pages that are not freed either, so nothing dangles)
    mov eax, UBF_ERR_MAP
    jmp .ret
.mapped:

    ; ---- 13. the record ----
    mov [r13 + ubf_prog_t.base], r15
    mov [r13 + ubf_prog_t.phys], r14
    mov rax, [rbx + UBF_H_MEM_SIZE]
    mov [r13 + ubf_prog_t.size], rax
    test byte [rbx + UBF_H_FLAGS], UBF_FLAG_ENTRY
    jz .no_entry
    mov rax, [rbx + UBF_H_ENTRY]
    add rax, r15
    mov [r13 + ubf_prog_t.entry], rax
.no_entry:
    movzx eax, word [rbx + UBF_H_KIND]
    mov [r13 + ubf_prog_t.kind], eax
    mov eax, [rbx + UBF_H_STACK]
    mov [r13 + ubf_prog_t.stack], eax
    mov eax, [rbx + UBF_H_EXP_OFF]
    add rax, rbx
    mov [r13 + ubf_prog_t.exports], rax
    mov eax, [rbx + UBF_H_EXP_COUNT]
    mov [r13 + ubf_prog_t.nexports], rax
    mov eax, [rbx + UBF_H_STR_OFF]
    add rax, rbx
    mov [r13 + ubf_prog_t.strtab], rax
    xor eax, eax
    jmp .ret

.format:
    mov eax, UBF_ERR_FORMAT
    jmp .ret
.digest:
    mov eax, UBF_ERR_DIGEST
    jmp .ret
.cpu:
    mov eax, UBF_ERR_CPU
    jmp .ret
.nomem_free:
    mov eax, UBF_ERR_NOMEM
.fail_free:
    mov rdi, r14
    mov rsi, [rsp + LF_PAGES]
    call phys_free_pages
    jmp .ret
.nomem:
    mov eax, UBF_ERR_NOMEM
.ret:
    add rsp, LF_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; .in_file: ESI = an offset, RAX = a length -> CF set unless the range lies
; inside the file. Clobbers RAX.
.in_file:
    add rax, rsi
    cmp rax, r12
    ja .out
    clc
    ret
.out:
    stc
    ret

; .seg_ptr / .seg_ptr_r8: segment R15D / R8D -> RDI = its entry. Clobbers RAX.
.seg_ptr:
    mov r8d, r15d
.seg_ptr_r8:
    mov eax, [rbx + UBF_H_SEG_OFF]
    mov edi, r8d
    shl rdi, 5
    add rdi, rax
    add rdi, rbx
    ret

; .imp_ptr / .imp_ptr_r8: import R15D / R8D -> RDI = its entry. Clobbers RAX.
.imp_ptr:
    mov r8d, r15d
.imp_ptr_r8:
    mov eax, [rbx + UBF_H_IMP_OFF]
    mov edi, r8d
    shl rdi, 4
    add rdi, rax
    add rdi, rbx
    ret

; .in_segment: ESI = an image offset, EDX = a segment type (0: any with
; bytes) -> CF set unless [ESI, ESI + 8) lies in such a segment's file
; bytes. Clobbers RAX, RCX, RDI, R8, R9.
.in_segment:
    xor r9d, r9d
.in_seg_next:
    cmp r9d, [rbx + UBF_H_SEG_COUNT]
    jae .out
    mov r8d, r9d
    call .seg_ptr_r8
    inc r9d
    mov eax, [rdi + UBF_SEG_TYPE]
    cmp eax, UBF_SEG_BSS
    je .in_seg_next
    test edx, edx
    jz .type_ok
    cmp eax, edx
    jne .in_seg_next
.type_ok:
    mov rax, [rdi + UBF_SEG_MEM_OFF]
    cmp rsi, rax
    jb .in_seg_next
    mov ecx, [rdi + UBF_SEG_FILE_SIZE]
    add rax, rcx                    ; the end of its bytes
    lea rcx, [rsi + 8]
    cmp rcx, rax
    ja .in_seg_next
    clc
    ret

; -----------------------------------------------------------------------------
; ubf_cpu_features — the UBF_CPU_* bits this CPU (and the state the kernel
; enabled) provides
; Output: EAX = the bits
; Clobbers: RCX, RDX, R8, R9
; -----------------------------------------------------------------------------
global ubf_cpu_features
ubf_cpu_features:
    push rbx
    xor r8d, r8d                    ; R8D = the result
    xor r9d, r9d                    ; R9D = XCR0, if readable

    mov eax, 1
    xor ecx, ecx
    cpuid
    bt ecx, 20
    jnc .no_sse42
    or r8d, UBF_CPU_SSE42
.no_sse42:
    bt ecx, 25
    jnc .no_aes
    or r8d, UBF_CPU_AES
.no_aes:
    bt ecx, 27                      ; OSXSAVE: XCR0 can be read
    jnc .no_xcr0
    push rcx
    xor ecx, ecx
    xgetbv
    mov r9d, eax
    pop rcx
.no_xcr0:
    mov eax, r9d
    and eax, 6
    cmp eax, 6                      ; SSE and AVX state enabled
    jne .no_avx
    bt ecx, 28
    jnc .no_avx
    or r8d, UBF_CPU_AVX
.no_avx:

    mov eax, 7
    xor ecx, ecx
    cpuid
    test r8d, UBF_CPU_AVX
    jz .no_avx2
    bt ebx, 5
    jnc .no_avx2
    or r8d, UBF_CPU_AVX2
.no_avx2:
    bt ebx, 3
    jnc .no_bmi
    bt ebx, 8
    jnc .no_bmi
    or r8d, UBF_CPU_BMI
.no_bmi:
    bt ebx, 29
    jnc .no_sha
    or r8d, UBF_CPU_SHA
.no_sha:
    mov eax, r9d
    and eax, 0xE6
    cmp eax, 0xE6                   ; opmask and ZMM state enabled too
    jne .done
    bt ebx, 16
    jnc .done
    or r8d, UBF_CPU_AVX512F
    bt ebx, 30
    jnc .done
    or r8d, UBF_CPU_AVX512BW
.done:
    mov eax, r8d
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubf_start — start a loaded application or command as a fiber
; Input:  RDI = ubf_prog_t* (from ubf_load), RSI = its start block (RDI at its
;         entry point)
; Output: RAX = the fiber's FCB, or 0 (a library, or no fiber available)
; -----------------------------------------------------------------------------
global ubf_start
ubf_start:
    mov rax, [rdi + ubf_prog_t.entry]
    test rax, rax
    jz .none
    mov rdi, rax
    mov rdx, PRIO_NORMAL
    mov rcx, FIBER_RESTART_NEVER
    jmp fiber_create
.none:
    xor eax, eax
    ret

%endif ; KERNEL_EXEC_UBF_LOAD_ASM
