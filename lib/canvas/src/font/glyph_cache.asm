; ============================================================================
; Glyph Cache — Rendered Bitmap Cache (glyph id + size -> coverage mask)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

; struct offsets (hoisted above use)
%define GlyphCache_size    32
%define GlyphEntry_size    48
%define GLYPH_CACHE_DEFAULT_CAP  256

section .text

struc GlyphCache
    .entries:       resq 1
    .cap:           resq 1
    .count:         resq 1
    .arena:         resq 1
endstruc

struc GlyphEntry
    .key:           resq 1  ; (glyph<<32)|size
    .mask:          resq 1
    .width:         resd 1
    .height:        resd 1
    .bearing_x:     resd 1
    .bearing_y:     resd 1
    .advance:       resd 1
    .next:          resq 1
endstruc


; ---------------------------------------------------------------------------
; glyph_cache_init
; ---------------------------------------------------------------------------
global glyph_cache_init
glyph_cache_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, r12
    mov rsi, GlyphCache_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov rdi, r12
    mov rsi, GLYPH_CACHE_DEFAULT_CAP
    shl rsi, 3
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + GlyphCache.entries], rax
    mov qword [rbx + GlyphCache.cap], GLYPH_CACHE_DEFAULT_CAP
    mov qword [rbx + GlyphCache.count], 0
    mov qword [rbx + GlyphCache.arena], r12
    ; zero buckets
    mov rdi, rax
    mov rcx, GLYPH_CACHE_DEFAULT_CAP
    xor eax, eax
    rep stosq
    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; glyph_cache_lookup
;   IN: rdi = cache, rsi = glyph id, rdx = pixel size
;   OUT: rax = entry* or 0
; ---------------------------------------------------------------------------
global glyph_cache_lookup
glyph_cache_lookup:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    mov rax, r12
    shl rax, 32
    or rax, r13
    mov rcx, [rbx + GlyphCache.cap]
    xor rdx, rdx
    div rcx
    mov rcx, [rbx + GlyphCache.entries]
    mov rax, [rcx + rdx * 8]
.loop:
    test rax, rax
    jz .miss
    mov rdx, r12
    shl rdx, 32
    or rdx, r13
    cmp [rax + GlyphEntry.key], rdx
    je .hit
    mov rax, [rax + GlyphEntry.next]
    jmp .loop
.hit:
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.miss:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; glyph_cache_insert
; ---------------------------------------------------------------------------
global glyph_cache_insert
glyph_cache_insert:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rax, [r12 + GlyphEntry.key]
    mov rcx, [rbx + GlyphCache.cap]
    xor edx, edx
    div rcx             ; rdx = bucket
    mov rcx, [rbx + GlyphCache.entries]
    mov r8, [rcx + rdx * 8]   ; old head
    mov [r12 + GlyphEntry.next], r8
    mov [rcx + rdx * 8], r12  ; new head
    inc qword [rbx + GlyphCache.count]
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
