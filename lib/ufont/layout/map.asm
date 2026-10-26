; =============================================================================
; Utkarsha OS — lib/ufont/layout/map.asm
; =============================================================================
; The shaping plan. Features are added in order with flags and a value,
; pauses (a routine run between stages) split them into stages; compiling
; sorts and merges the features, gives each found in the font a mask (the
; global bit when it is on everywhere with value 1), and per table lists
; the lookups of every stage, sorted by index with duplicates merged, the
; required feature's lookups in the stage of its tag (else the first).
;
;   ufl_map_init                                 the builder's arrays (state)
;   ufl_map_add_feature(edi = tag, esi = flags, edx = value)
;   ufl_map_enable(edi = tag, esi = flags, edx = value)   flags | F_GLOBAL
;   ufl_map_disable(edi = tag)
;   ufl_map_add_gsub_pause(rdi = routine or 0)
;   ufl_map_compile                              -> eax 0 / -1 (no memory)
;   ufl_map_get_mask(edi = tag), ufl_map_get_1_mask(edi = tag) -> eax (0: not found)
;   ufl_map_stage_lookups(edi = table, esi = tag) -> rax = LK records of the
;       feature's stage, ecx = how many
; =============================================================================

%include "ufont.inc"
%include "shape.inc"

extern arena_alloc
extern ufl_otl_feature_index
extern ufl_otl_feature_tag
extern ufl_otl_feature_lookups
extern ufl_otl_lookup_count

section .text

; rdi = bytes -> rax (0: none; S_ERR set)
map_alloc:
    mov rsi, rdi
    mov rdi, [r15 + S_ARENA]
    sub rsp, 8
    call arena_alloc
    add rsp, 8
    test rax, rax
    jnz .ok
    mov byte [r15 + S_ERR], 1
.ok:
    ret

global ufl_map_init
ufl_map_init:
    sub rsp, 8
    mov dword [r15 + S_NFI], 0
    mov dword [r15 + S_CUR], 0
    mov dword [r15 + S_CUR + 4], 0
    mov dword [r15 + S_NPA], 0
    mov dword [r15 + S_NPA + 4], 0
    mov edi, MAX_FEATURES * FI_SIZE
    call map_alloc
    test rax, rax
    jz .fail
    mov [r15 + S_FI], rax
    mov edi, MAX_PAUSES * PA_SIZE
    call map_alloc
    test rax, rax
    jz .fail
    mov [r15 + S_PA], rax
    mov edi, MAX_PAUSES * PA_SIZE
    call map_alloc
    test rax, rax
    jz .fail
    mov [r15 + S_PA + 8], rax
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, -1
    add rsp, 8
    ret

global ufl_map_enable
ufl_map_enable:
    or esi, F_GLOBAL
    jmp ufl_map_add_feature

global ufl_map_disable
ufl_map_disable:
    mov esi, F_GLOBAL
    xor edx, edx
    jmp ufl_map_add_feature

global ufl_map_add_feature
ufl_map_add_feature:
    mov eax, [r15 + S_NFI]
    cmp eax, MAX_FEATURES
    jae .full
    imul ecx, eax, FI_SIZE
    add rcx, [r15 + S_FI]
    inc eax
    mov [r15 + S_NFI], eax
    mov [rcx + FI_TAG], edi
    mov [rcx + FI_SEQ], eax
    mov [rcx + FI_MAX], edx
    mov [rcx + FI_FLAGS], esi
    xor eax, eax
    test esi, F_GLOBAL
    cmovnz eax, edx
    mov [rcx + FI_DEFAULT], eax
    mov eax, [r15 + S_CUR]
    mov [rcx + FI_STAGE], eax
    mov eax, [r15 + S_CUR + 4]
    mov [rcx + FI_STAGE + 4], eax
.full:
    ret

global ufl_map_add_gsub_pause
ufl_map_add_gsub_pause:
    mov eax, [r15 + S_NPA]
    cmp eax, MAX_PAUSES - 1
    jae .full
    mov rcx, rax
    shl rcx, 4
    add rcx, [r15 + S_PA]
    mov edx, [r15 + S_CUR]
    mov [rcx + PA_STAGE], rdx
    mov [rcx + PA_FUNC], rdi
    inc dword [r15 + S_NPA]
    inc dword [r15 + S_CUR]
.full:
    ret

; ----------------------------------------------------------------------------
; ufl_map_compile
; ----------------------------------------------------------------------------
%define MC_REQIDX   0                   ; [2] required feature index (-1)
%define MC_REQTAG   8                   ; [2]
%define MC_REQSTAGE 16                  ; [2]
%define MC_NEXTBIT  24
%define MC_T        28                  ; table being listed
%define MC_STAGE    32
%define MC_PI       36                  ; next pause
%define MC_LAST     40                  ; lookups before this stage
%define MC_NLOOKUPS 44                  ; lookups the table has
%define MC_SIZE     48

global ufl_map_compile
ufl_map_compile:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, MC_SIZE
    ; arrays
    mov edi, MAX_FEATURES * FM_SIZE
    call map_alloc
    test rax, rax
    jz .fail
    mov [r15 + S_FEATS], rax
    mov dword [r15 + S_NFEATS], 0
    xor ebx, ebx
.arrays:
    mov dword [r15 + S_NLK + rbx * 4], 0
    mov edi, MAX_PAUSES * ST_SIZE
    call map_alloc
    test rax, rax
    jz .fail
    mov [r15 + S_ST + rbx * 8], rax
    mov dword [r15 + S_NST + rbx * 4], 0
    inc ebx
    cmp ebx, 2
    jb .arrays
    ; required features
    xor ebx, ebx
.req:
    mov dword [rsp + MC_REQIDX + rbx * 4], -1
    mov dword [rsp + MC_REQTAG + rbx * 4], 0
    mov dword [rsp + MC_REQSTAGE + rbx * 4], 0
    mov rax, [r15 + S_LS + rbx * 8]
    test rax, rax
    jz .req_next
    BE16 esi, [rax + 2]
    cmp esi, 0xFFFF
    je .req_next
    mov [rsp + MC_REQIDX + rbx * 4], esi
    mov edi, ebx
    call ufl_otl_feature_tag
    mov [rsp + MC_REQTAG + rbx * 4], eax
.req_next:
    inc ebx
    cmp ebx, 2
    jb .req
    ; sort the features by tag (as a big-endian number), then order added
    mov r12, [r15 + S_FI]
    mov r13d, [r15 + S_NFI]
    mov ebx, 1
.sort:
    cmp ebx, r13d
    jae .sorted
    imul eax, ebx, FI_SIZE
    movdqu xmm0, [r12 + rax]
    movdqu xmm1, [r12 + rax + 12]       ; FI_SIZE 28: bytes 12 .. 27
    mov r8d, [r12 + rax + FI_TAG]
    bswap r8d
    mov ecx, ebx
.sort_in:
    test ecx, ecx
    jz .sort_put
    imul eax, ecx, FI_SIZE
    mov r9d, [r12 + rax - FI_SIZE + FI_TAG]
    bswap r9d
    cmp r9d, r8d
    jbe .sort_put                       ; equal tags keep their order
    movdqu xmm2, [r12 + rax - FI_SIZE]
    movdqu xmm3, [r12 + rax - FI_SIZE + 12]
    movdqu [r12 + rax], xmm2
    movdqu [r12 + rax + 12], xmm3
    dec ecx
    jmp .sort_in
.sort_put:
    imul eax, ecx, FI_SIZE
    movdqu [r12 + rax], xmm0
    movdqu [r12 + rax + 12], xmm1
    inc ebx
    jmp .sort
.sorted:
    ; merge features with the same tag into the first
    xor ebx, ebx                        ; i
    xor ebp, ebp                        ; j (merged count - 1)
    test r13d, r13d
    jz .merged
    inc ebx
.merge:
    cmp ebx, r13d
    jae .merge_done
    imul eax, ebx, FI_SIZE
    lea rsi, [r12 + rax]                ; f[i]
    imul eax, ebp, FI_SIZE
    lea rdi, [r12 + rax]                ; f[j]
    mov eax, [rsi + FI_TAG]
    cmp eax, [rdi + FI_TAG]
    je .same
    inc ebp
    imul eax, ebp, FI_SIZE
    lea rdi, [r12 + rax]
    movdqu xmm0, [rsi]
    movdqu xmm1, [rsi + 12]
    movdqu [rdi], xmm0
    movdqu [rdi + 12], xmm1
    jmp .merge_next
.same:
    mov eax, [rsi + FI_FLAGS]
    test eax, F_GLOBAL
    jz .not_global
    or dword [rdi + FI_FLAGS], F_GLOBAL
    mov ecx, [rsi + FI_MAX]
    mov [rdi + FI_MAX], ecx
    mov ecx, [rsi + FI_DEFAULT]
    mov [rdi + FI_DEFAULT], ecx
    jmp .fallback
.not_global:
    and dword [rdi + FI_FLAGS], ~F_GLOBAL
    mov ecx, [rsi + FI_MAX]
    cmp ecx, [rdi + FI_MAX]
    jbe .fallback
    mov [rdi + FI_MAX], ecx
.fallback:
    and eax, F_HAS_FALLBACK
    or [rdi + FI_FLAGS], eax
    mov ecx, [rsi + FI_STAGE]
    cmp ecx, [rdi + FI_STAGE]
    jae .s1
    mov [rdi + FI_STAGE], ecx
.s1:
    mov ecx, [rsi + FI_STAGE + 4]
    cmp ecx, [rdi + FI_STAGE + 4]
    jae .merge_next
    mov [rdi + FI_STAGE + 4], ecx
.merge_next:
    inc ebx
    jmp .merge
.merge_done:
    lea r13d, [rbp + 1]
.merged:
    ; masks for the features found
    mov dword [r15 + S_GMASK], GLOBAL_MASK
    mov dword [rsp + MC_NEXTBIT], 4
    xor ebx, ebx
.feature:
    cmp ebx, r13d
    jae .features_done
    imul eax, ebx, FI_SIZE
    lea r14, [r12 + rax]                ; FI
    mov eax, [r14 + FI_MAX]
    test eax, eax
    jz .feature_next
    xor ecx, ecx                        ; bits
    test dword [r14 + FI_FLAGS], F_GLOBAL
    jz .bits
    cmp eax, 1
    je .have_bits
.bits:
    bsr ecx, eax
    inc ecx
    cmp ecx, 8
    jbe .have_bits
    mov ecx, 8
.have_bits:
    mov ebp, ecx
    mov eax, [rsp + MC_NEXTBIT]
    add eax, ecx
    cmp eax, 31
    jae .feature_next
    ; its index in each table
    imul eax, [r15 + S_NFEATS], FM_SIZE
    add rax, [r15 + S_FEATS]
    push rax
    sub rsp, 8
    xor edx, edx                        ; found
    mov [rsp + 8 + 8 + MC_T], edx
.index:
    mov ecx, [rsp + 16 + MC_T]
    mov eax, [r14 + FI_TAG]
    cmp eax, [rsp + 16 + MC_REQTAG + rcx * 4]
    jne .not_req
    mov eax, [r14 + FI_STAGE + rcx * 4]
    mov [rsp + 16 + MC_REQSTAGE + rcx * 4], eax
.not_req:
    mov edi, ecx
    mov esi, [r14 + FI_TAG]
    call ufl_otl_feature_index
    mov ecx, [rsp + 16 + MC_T]
    mov rdx, [rsp + 8]
    mov [rdx + FM_INDEX + rcx * 4], eax
    inc ecx
    mov [rsp + 16 + MC_T], ecx
    cmp ecx, 2
    jb .index
    add rsp, 8
    pop rdx
    cmp dword [rdx + FM_INDEX], -1
    jne .found
    cmp dword [rdx + FM_INDEX + 4], -1
    jne .found
    test dword [r14 + FI_FLAGS], F_HAS_FALLBACK
    jz .feature_next
.found:
    mov eax, [r14 + FI_TAG]
    mov [rdx + FM_TAG], eax
    mov eax, [r14 + FI_STAGE]
    mov [rdx + FM_STAGE], eax
    mov eax, [r14 + FI_STAGE + 4]
    mov [rdx + FM_STAGE + 4], eax
    mov eax, [r14 + FI_FLAGS]
    mov [rdx + FM_FLAGS], eax
    test eax, F_GLOBAL
    jz .own_bits
    cmp dword [r14 + FI_MAX], 1
    jne .own_bits
    mov dword [rdx + FM_MASK], GLOBAL_MASK
    mov dword [rdx + FM_MASK1], GLOBAL_MASK
    jmp .added
.own_bits:
    mov ecx, [rsp + MC_NEXTBIT]
    mov eax, 1
    shl eax, cl                         ; 1 << shift
    mov [rdx + FM_MASK1], eax
    lea ecx, [rcx + rbp]
    mov r8d, 1
    shl r8d, cl
    sub r8d, eax                        ; the mask
    mov [rdx + FM_MASK], r8d
    mov [rsp + MC_NEXTBIT], ecx
    mov eax, [r14 + FI_DEFAULT]
    sub ecx, ebp
    shl eax, cl
    and eax, r8d
    or [r15 + S_GMASK], eax
.added:
    inc dword [r15 + S_NFEATS]
.feature_next:
    inc ebx
    jmp .feature
.features_done:
    ; the lookup arrays: room for every lookup of every feature found (and
    ; the required one)
    mov dword [rsp + MC_T], 0
.room:
    mov ecx, [rsp + MC_T]
    xor ebp, ebp                        ; entries
    mov esi, [rsp + MC_REQIDX + rcx * 4]
    cmp esi, -1
    je .room_features
    mov edi, ecx
    call ufl_otl_feature_lookups
    add ebp, ecx
.room_features:
    xor ebx, ebx
.room_f:
    cmp ebx, [r15 + S_NFEATS]
    jae .room_alloc
    imul eax, ebx, FM_SIZE
    add rax, [r15 + S_FEATS]
    mov ecx, [rsp + MC_T]
    mov esi, [rax + FM_INDEX + rcx * 4]
    cmp esi, -1
    je .room_next
    mov edi, ecx
    call ufl_otl_feature_lookups
    add ebp, ecx
.room_next:
    inc ebx
    jmp .room_f
.room_alloc:
    mov ecx, [rsp + MC_T]
    mov [r15 + S_LKCAP + rcx * 4], ebp
    imul edi, ebp, LK_SIZE
    add edi, LK_SIZE
    call map_alloc
    test rax, rax
    jz .fail
    mov ecx, [rsp + MC_T]
    mov [r15 + S_LK + rcx * 8], rax
    inc dword [rsp + MC_T]
    cmp dword [rsp + MC_T], 2
    jb .room
    ; the last pause of each table
    mov rdi, 0
    call map_add_gsub_pause_end
    ; lookups, stage by stage
    mov dword [rsp + MC_T], 0
.table:
    mov ecx, [rsp + MC_T]
    mov edi, ecx
    call ufl_otl_lookup_count
    mov [rsp + MC_NLOOKUPS], eax
    mov dword [rsp + MC_STAGE], 0
    mov dword [rsp + MC_PI], 0
    mov dword [rsp + MC_LAST], 0
.stage:
    mov ecx, [rsp + MC_T]
    ; the stages run to the last pause's
    mov eax, [r15 + S_NPA + rcx * 4]
    dec eax
    shl rax, 4
    add rax, [r15 + S_PA + rcx * 8]
    mov eax, [rax + PA_STAGE]
    cmp [rsp + MC_STAGE], eax
    ja .table_done
    ; the required feature
    mov eax, [rsp + MC_REQIDX + rcx * 4]
    cmp eax, -1
    je .stage_features
    mov edx, [rsp + MC_REQSTAGE + rcx * 4]
    cmp edx, [rsp + MC_STAGE]
    jne .stage_features
    mov edi, ecx
    mov esi, eax
    mov edx, GLOBAL_MASK
    mov ecx, 3                          ; auto joiners, not per syllable
    call map_add_lookups
.stage_features:
    xor ebx, ebx
.sf:
    cmp ebx, [r15 + S_NFEATS]
    jae .stage_sort
    imul eax, ebx, FM_SIZE
    add rax, [r15 + S_FEATS]
    mov ecx, [rsp + MC_T]
    mov edx, [rax + FM_STAGE + rcx * 4]
    cmp edx, [rsp + MC_STAGE]
    jne .sf_next
    mov esi, [rax + FM_INDEX + rcx * 4]
    cmp esi, -1
    je .sf_next
    mov edx, [rax + FM_MASK]
    mov r8d, [rax + FM_FLAGS]
    xor ecx, ecx
    test r8d, F_MANUAL_ZWNJ
    jnz .no_zwnj
    or ecx, 1
.no_zwnj:
    test r8d, F_MANUAL_ZWJ
    jnz .no_zwj
    or ecx, 2
.no_zwj:
    test r8d, F_PER_SYLLABLE
    jz .not_ps
    or ecx, 4
.not_ps:
    mov edi, [rsp + MC_T]
    call map_add_lookups
.sf_next:
    inc ebx
    jmp .sf
.stage_sort:
    call map_sort_stage
    ; a pause after this stage?
    mov ecx, [rsp + MC_T]
    mov eax, [rsp + MC_PI]
    cmp eax, [r15 + S_NPA + rcx * 4]
    jae .stage_next
    shl rax, 4
    add rax, [r15 + S_PA + rcx * 8]
    mov edx, [rax + PA_STAGE]
    cmp edx, [rsp + MC_STAGE]
    jne .stage_next
    mov rdx, [rax + PA_FUNC]
    mov eax, [r15 + S_NST + rcx * 4]
    shl rax, 4
    add rax, [r15 + S_ST + rcx * 8]
    mov r8d, [r15 + S_NLK + rcx * 4]
    mov [rax + ST_LAST], r8
    mov [rax + ST_PAUSE], rdx
    inc dword [r15 + S_NST + rcx * 4]
    inc dword [rsp + MC_PI]
.stage_next:
    mov eax, [r15 + S_NLK + rcx * 4]
    mov [rsp + MC_LAST], eax
    inc dword [rsp + MC_STAGE]
    jmp .stage
.table_done:
    inc dword [rsp + MC_T]
    cmp dword [rsp + MC_T], 2
    jb .table
    xor eax, eax
    cmp byte [r15 + S_ERR], 0
    je .out
.fail:
    mov eax, -1
.out:
    add rsp, MC_SIZE
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; the final pause of both tables (HarfBuzz's compile adds one to each)
map_add_gsub_pause_end:
    mov ecx, 0
.t:
    mov eax, [r15 + S_NPA + rcx * 4]
    shl rax, 4
    add rax, [r15 + S_PA + rcx * 8]
    mov edx, [r15 + S_CUR + rcx * 4]
    mov [rax + PA_STAGE], rdx
    mov qword [rax + PA_FUNC], 0
    inc dword [r15 + S_NPA + rcx * 4]
    inc dword [r15 + S_CUR + rcx * 4]
    inc ecx
    cmp ecx, 2
    jb .t
    ret

; map_add_lookups — edi = table, esi = feature index, edx = mask, ecx = bits
;   (1 auto ZWNJ, 2 auto ZWJ, 4 per syllable); [rsp + 8 + ...] is the
;   caller's frame: the table's lookup count read from MC_NLOOKUPS
map_add_lookups:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov ebx, edi
    mov r12d, edx
    mov r13d, ecx
    call ufl_otl_feature_lookups
    mov r14, rax
    mov ebp, ecx
    mov r9d, [rsp + 48 + MC_NLOOKUPS]   ; 5 pushes + return address
.each:
    test ebp, ebp
    jz .done
    BE16 eax, [r14]
    add r14, 2
    dec ebp
    cmp eax, r9d
    jae .each
    mov ecx, [r15 + S_NLK + rbx * 4]
    cmp ecx, [r15 + S_LKCAP + rbx * 4]
    jae .done
    imul ecx, ecx, LK_SIZE
    add rcx, [r15 + S_LK + rbx * 8]
    mov [rcx + LK_INDEX], eax
    mov [rcx + LK_MASK], r12d
    mov eax, r13d
    and eax, 1
    mov [rcx + LK_AZWNJ], al
    mov eax, r13d
    shr eax, 1
    and eax, 1
    mov [rcx + LK_AZWJ], al
    mov eax, r13d
    shr eax, 2
    and eax, 1
    mov [rcx + LK_PERSYL], al
    inc dword [r15 + S_NLK + rbx * 4]
    jmp .each
.done:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; sort the stage's lookups (from MC_LAST) by index as HarfBuzz does (not
; stably: the merge keeps the first's flags), merging equal indices: masks
; or-ed, auto joiners and-ed. Caller's frame at [rsp + 8].
map_sort_stage:
    push rbx
    push r12
    push r13
    mov ecx, [rsp + 32 + MC_T]
    mov r12, [r15 + S_LK + rcx * 8]
    mov r13d, [rsp + 32 + MC_LAST]      ; start
    mov esi, [r15 + S_NLK + rcx * 4]
    sub esi, r13d
    cmp esi, 2
    jb .sorted
    imul edi, r13d, LK_SIZE
    add rdi, r12
    call map_qsort
.sorted:
    mov ecx, [rsp + 32 + MC_T]
    mov r8d, [r15 + S_NLK + rcx * 4]    ; end
    ; merge
    cmp r13d, r8d
    jae .out
    mov edx, r13d                       ; j
    lea ebx, [r13 + 1]
.merge:
    cmp ebx, r8d
    jae .merged
    imul eax, ebx, LK_SIZE
    imul r9d, edx, LK_SIZE
    mov r10d, [r12 + rax + LK_INDEX]
    cmp r10d, [r12 + r9 + LK_INDEX]
    jne .other
    mov r10d, [r12 + rax + LK_MASK]
    or [r12 + r9 + LK_MASK], r10d
    mov r10b, [r12 + rax + LK_AZWNJ]
    and [r12 + r9 + LK_AZWNJ], r10b
    mov r10b, [r12 + rax + LK_AZWJ]
    and [r12 + r9 + LK_AZWJ], r10b
    jmp .merge_next
.other:
    inc edx
    imul r9d, edx, LK_SIZE
    mov r10, [r12 + rax]
    mov [r12 + r9], r10
    mov r10d, [r12 + rax + 8]
    mov [r12 + r9 + 8], r10d
.merge_next:
    inc ebx
    jmp .merge
.merged:
    inc edx
    mov [r15 + S_NLK + rcx * 4], edx
.out:
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; map_qsort — rdi = LK records, esi = count: by index, as HarfBuzz's hb_qsort
;   (sort_r_simple): insertion sort below 10, else a three-way quicksort on
;   the median of the second, middle and second-last records
; ----------------------------------------------------------------------------
%define QS_PRE      0                   ; the right end of the equal items
%define QS_PIVOT    8                   ; the pivot's index
%define QS_LAST     16
%define QS_SIZE     32

map_qsort:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, QS_SIZE
    mov rbx, rdi                        ; b
    mov eax, esi
    imul rax, rax, LK_SIZE
    lea r12, [rbx + rax]                ; end
    cmp esi, 10
    jae .quick
    lea r13, [rbx + LK_SIZE]            ; pi
.ins:
    cmp r13, r12
    jae .out
    mov r14, r13                        ; pj
.ins_in:
    cmp r14, rbx
    jbe .ins_next
    mov eax, [r14 - LK_SIZE + LK_INDEX]
    cmp eax, [r14 + LK_INDEX]
    jbe .ins_next
    lea rdi, [r14 - LK_SIZE]
    mov rsi, r14
    mov ecx, 1
    call qs_swapn
    sub r14, LK_SIZE
    jmp .ins_in
.ins_next:
    add r13, LK_SIZE
    jmp .ins
.quick:
    lea rax, [r12 - LK_SIZE]
    mov [rsp + QS_LAST], rax
    lea r8, [rbx + LK_SIZE]             ; the median of these
    mov eax, esi
    shr eax, 1
    imul rax, rax, LK_SIZE
    lea r9, [rbx + rax]
    mov r10, [rsp + QS_LAST]
    sub r10, LK_SIZE
    mov eax, [r8 + LK_INDEX]
    cmp eax, [r9 + LK_INDEX]
    jbe .m1
    xchg r8, r9
.m1:
    mov eax, [r9 + LK_INDEX]
    cmp eax, [r10 + LK_INDEX]
    jbe .m2
    xchg r9, r10
    mov eax, [r8 + LK_INDEX]
    cmp eax, [r9 + LK_INDEX]
    jbe .m2
    xchg r8, r9
.m2:
    mov rsi, [rsp + QS_LAST]            ; the pivot to the end
    cmp r9, rsi
    je .pivot
    mov rdi, r9
    mov ecx, 1
    call qs_swapn
.pivot:
    mov rax, [rsp + QS_LAST]
    mov eax, [rax + LK_INDEX]
    mov [rsp + QS_PIVOT], eax
    mov rbp, rbx                        ; ple
    mov r13, rbx                        ; pl
    mov r14, [rsp + QS_LAST]            ; pr
    mov [rsp + QS_PRE], r14
.outer:
    cmp r13, r14
    jae .partitioned
.left:
    ; from the left: equal items to the far left, up to a greater one
    cmp r13, r14
    jae .left_done
    mov eax, [r13 + LK_INDEX]
    cmp eax, [rsp + QS_PIVOT]
    ja .left_done
    jne .left_next
    cmp rbp, r13
    jae .left_equal
    mov rdi, rbp
    mov rsi, r13
    mov ecx, 1
    call qs_swapn
.left_equal:
    add rbp, LK_SIZE
.left_next:
    add r13, LK_SIZE
    jmp .left
.left_done:
    cmp r13, r14
    jae .partitioned
.right:
    ; from the right: equal items to the far right, down to a lesser one
    cmp r13, r14
    jae .outer
    sub r14, LK_SIZE
    mov eax, [r14 + LK_INDEX]
    cmp eax, [rsp + QS_PIVOT]
    ja .right
    jb .right_less
    sub qword [rsp + QS_PRE], LK_SIZE
    cmp r14, [rsp + QS_PRE]
    jae .right
    mov rdi, r14
    mov rsi, [rsp + QS_PRE]
    mov ecx, 1
    call qs_swapn
    jmp .right
.right_less:
    cmp r13, r14
    jae .right_swapped
    mov rdi, r13
    mov rsi, r14
    mov ecx, 1
    call qs_swapn
.right_swapped:
    add r13, LK_SIZE
    jmp .outer
.partitioned:
    mov r13, r14                        ; pl = pr
    ; the equal items into the middle
    mov rdi, rbx
    mov rsi, rbp
    sub rsi, rbx
    mov rdx, r13
    sub rdx, rbp
    call qs_blocks
    mov rdi, r14
    mov rsi, [rsp + QS_PRE]
    sub rsi, r14
    mov rdx, r12
    sub rdx, [rsp + QS_PRE]
    call qs_blocks
    ; the lesser and the greater
    mov rax, r13
    sub rax, rbp
    xor edx, edx
    mov ecx, LK_SIZE
    div rcx
    mov rdi, rbx
    mov esi, eax
    call map_qsort
    mov rax, [rsp + QS_PRE]
    sub rax, r14
    mov rdi, r12
    sub rdi, rax
    xor edx, edx
    mov ecx, LK_SIZE
    div rcx
    mov esi, eax
    call map_qsort
.out:
    add rsp, QS_SIZE
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; rdi, rsi = records, ecx = how many: swapped
qs_swapn:
    test ecx, ecx
    jz .out
    mov rax, [rdi]
    mov rdx, [rsi]
    mov [rdi], rdx
    mov [rsi], rax
    mov eax, [rdi + 8]
    mov edx, [rsi + 8]
    mov [rdi + 8], edx
    mov [rsi + 8], eax
    add rdi, LK_SIZE
    add rsi, LK_SIZE
    dec ecx
    jmp qs_swapn
.out:
    ret

; rdi = start, rsi / rdx = two adjacent blocks' bytes: put in the opposite
;   order with the smallest swap
qs_blocks:
    test rsi, rsi
    jz .out
    test rdx, rdx
    jz .out
    cmp rsi, rdx
    jbe .second
    mov rax, rdx                        ; first nb bytes with those after na
    lea rsi, [rdi + rsi]
    jmp .swap
.second:
    mov rax, rsi
    lea rsi, [rdi + rdx]
.swap:
    xor edx, edx
    mov ecx, LK_SIZE
    div rcx
    mov ecx, eax
    jmp qs_swapn
.out:
    ret

; ----------------------------------------------------------------------------
; ufl_map_get_mask / ufl_map_get_1_mask — edi = tag -> eax
; ufl_map_feature — edi = tag -> rax = FM record, 0
; ----------------------------------------------------------------------------
global ufl_map_feature
ufl_map_feature:
    mov rax, [r15 + S_FEATS]
    mov ecx, [r15 + S_NFEATS]
.loop:
    test ecx, ecx
    jz .none
    cmp [rax + FM_TAG], edi
    je .out
    add rax, FM_SIZE
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.out:
    ret

global ufl_map_get_mask
ufl_map_get_mask:
    call ufl_map_feature
    test rax, rax
    jz .out
    mov eax, [rax + FM_MASK]
.out:
    ret

global ufl_map_get_1_mask
ufl_map_get_1_mask:
    call ufl_map_feature
    test rax, rax
    jz .out
    mov eax, [rax + FM_MASK1]
.out:
    ret

; ----------------------------------------------------------------------------
; ufl_map_stage_lookups — edi = table, esi = tag -> rax = LK records, ecx = count
; ----------------------------------------------------------------------------
global ufl_map_stage_lookups
ufl_map_stage_lookups:
    push rbx
    mov ebx, edi
    mov edi, esi
    call ufl_map_feature
    test rax, rax
    jz .none
    mov eax, [rax + FM_STAGE + rbx * 4]
    mov ecx, [r15 + S_NST + rbx * 4]
    cmp eax, ecx
    ja .none
    xor edx, edx                        ; start
    test eax, eax
    jz .start
    mov rdx, rax
    dec rdx
    shl rdx, 4
    add rdx, [r15 + S_ST + rbx * 8]
    mov edx, [rdx + ST_LAST]
.start:
    mov r8d, [r15 + S_NLK + rbx * 4]    ; end
    cmp eax, ecx
    jae .end
    shl rax, 4
    add rax, [r15 + S_ST + rbx * 8]
    mov r8d, [rax + ST_LAST]
.end:
    mov ecx, r8d
    sub ecx, edx
    jbe .none
    imul eax, edx, LK_SIZE
    add rax, [r15 + S_LK + rbx * 8]
    pop rbx
    ret
.none:
    xor eax, eax
    xor ecx, ecx
    pop rbx
    ret
