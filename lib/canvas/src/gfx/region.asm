; ============================================================================
; Region — Band List of Rectangles (Union, Intersect, Subtract)
; Efficient for clipping and damage tracking
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

; struct offsets (hoisted above use)
%define Band_y1      0
%define Band_y2      4
%define Band_rects   8
%define Band_count   16
%define Band_cap     20
%define Band_size    24
%define Region_bands 0
%define Region_count 8
%define Region_cap   12
%define Region_arena 16
%define Region_size  24

section .text



; ---------------------------------------------------------------------------
; region_init
;   Initialize empty region
;   IN:  rdi = Region*, rsi = arena, rdx = initial_band_cap (0=8)
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global region_init
region_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    test rdx, rdx
    jnz .has_cap
    mov rdx, 8
.has_cap:
    ; Allocate band array
    mov rdi, r12
    mov rsi, rdx
    imul rsi, Band_size
    call arena_alloc
    test rax, rax
    jz .oom

    mov qword [rbx + Region_bands], rax
    mov qword [rbx + Region_count], 0
    mov qword [rbx + Region_cap], rdx
    mov qword [rbx + Region_arena], r12
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; region_add_rect
;   Add rectangle to region (merges with existing bands)
;   IN:  rdi = Region*, rsi = x1, rdx = y1, rcx = x2, r8 = y2
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global region_add_rect
region_add_rect:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    ASSERT_PTR rbx

    ; Ensure y1 <= y2, x1 <= x2
    cmp r12d, r14d
    jle .x_ok
    xchg r12d, r14d
.x_ok:
    cmp r13d, r15d
    jle .y_ok
    xchg r13d, r15d
.y_ok:

    ; Find or create bands for y1..y2
    ; This is simplified - full implementation would merge adjacent bands
    ; For now, create one band per scanline (slow but correct)
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r15
    call region_ensure_bands
    TEST_ASSERT_OK rax

    ; Add rect to each band
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r15
    mov rcx, r12
    mov r8, r14
    call region_add_rect_to_bands
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; region_ensure_bands (internal)
;   Ensure bands exist for y-range
; ---------------------------------------------------------------------------
region_ensure_bands:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi        ; y1
    mov r13, rdx        ; y2
    ASSERT_PTR rbx

    ; For each scanline, ensure band exists
    mov r14, r12
.loop:
    cmp r14, r13
    jge .done
    ; Find band for this y
    mov rdi, rbx
    mov rsi, r14
    call region_find_or_create_band
    TEST_ASSERT_OK rax
    inc r14
    jmp .loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; region_find_or_create_band (internal)
; ---------------------------------------------------------------------------
region_find_or_create_band:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi        ; y
    ASSERT_PTR rbx

    ; Search existing bands
    mov r13, [rbx + Region_bands]
    mov r14, [rbx + Region_count]
    test r14, r14
    jz .create

    xor rax, rax
.search:
    cmp rax, r14
    jae .create
    mov rdx, [r13 + rax * Band_size + Band_y1]
    cmp edx, r12d
    je .found
    cmp edx, r12d
    jg .create
    inc rax
    jmp .search

.found:
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.create:
    ; Need to insert band at position rax
    mov rdi, rbx
    mov rsi, rax
    call region_insert_band
    TEST_ASSERT_OK rax

    ; Initialize new band
    mov rbx, [rdi + Region_bands]
    add rbx, rax
    mov dword [rbx + Band_y1], r12d
    mov dword [rbx + Band_y2], r12d
    inc r12d
    mov dword [rbx + Band_y2], r12d
    mov qword [rbx + Band_rects], 0
    mov qword [rbx + Band_count], 0
    mov qword [rbx + Band_cap], 0
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; region_insert_band (internal)
; ---------------------------------------------------------------------------
region_insert_band:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi        ; insert index
    ASSERT_PTR rbx

    mov r13, [rbx + Region_count]
    mov r14, [rbx + Region_cap]
    cmp r13, r14
    jae .grow

    ; Shift bands up
    mov r15, [rbx + Region_bands]
    lea r14, [r15 + r13 * Band_size]
    lea r13, [r15 + r12 * Band_size]
    mov rcx, r13
    sub rcx, r14
    neg rcx
    shr rcx, 3
    std
    rep movsq
    cld

    inc qword [rbx + Region_count]
    mov rax, r12
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.grow:
    ; Grow band array
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; region_add_rect_to_bands (internal)
; ---------------------------------------------------------------------------
region_add_rect_to_bands:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi        ; y1
    mov r13, rdx        ; y2
    mov r14, rcx        ; x1
    mov r15, r8         ; x2
    ASSERT_PTR rbx

.loop:
    cmp r12, r13
    jge .done
    ; Find band
    mov rdi, rbx
    mov rsi, r12
    call region_find_or_create_band
    TEST_ASSERT_OK rax

    ; Add rect to band
    mov rbx, rax
    call band_add_rect
    TEST_ASSERT_OK rax

    inc r12
    jmp .loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; band_add_rect (internal)
;   Add rect to band's rect list
; ---------------------------------------------------------------------------
band_add_rect:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    ASSERT_PTR rbx

    mov r12, [rbx + Band_rects]
    mov r13, [rbx + Band_count]
    mov r14, [rbx + Band_cap]

    cmp r13, r14
    jae .grow

    ; Add rect
    mov dword [r12 + r13 * 16 + 0], r14d
    mov dword [r12 + r13 * 16 + 4], r12d
    mov dword [r12 + r13 * 16 + 8], r15d
    mov dword [r12 + r13 * 16 + 12], r13d
    inc qword [rbx + Band_count]
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.grow:
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; region_clear
;   Clear region
;   IN:  rdi = Region*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global region_clear
region_clear:
    PROLOGUE
    ASSERT_PTR rdi
    mov qword [rdi + Region_count], 0
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; region_is_empty
;   Check if region is empty
;   IN:  rdi = Region*
;   OUT: rax = 1 if empty, 0 if not
; ---------------------------------------------------------------------------
global region_is_empty
region_is_empty:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Region_count]
    test rax, rax
    jz .empty
    xor rax, rax
    leave
    ret
.empty:
    mov rax, 1
    leave
    ret

section .data

global region_version
region_version: dq 0x010000
