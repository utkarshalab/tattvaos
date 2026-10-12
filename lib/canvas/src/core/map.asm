; ============================================================================
; Hash Map — Open Addressing with Linear Probing
; Arena-aware, power-of-2 capacity, FNV-1a hash
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

; ---------------------------------------------------------------------------
; map_init
;   Initialize hash map
;   IN:  rdi = map pointer (Map*)
;        rsi = arena pointer
;        rdx = initial capacity (power of 2, min 16)
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global map_init
map_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi        ; map
    mov r12, rsi        ; arena
    mov r13, rdx        ; capacity
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Ensure power of 2, min 16
    test r13, r13
    jnz .check_pow2
    mov r13, 16
.check_pow2:
    mov rax, r13
    dec rax
    test rax, r13
    jz .pow2_ok
    ; Round up to next power of 2
    bsr rax, r13
    inc rax
    mov r13, 1
    shl r13, cl
.pow2_ok:

    ; Allocate entries array
    mov rdi, r12
    mov rsi, r13
    shl rsi, 4          ; 16 bytes per entry (key_ptr, value_ptr)
    call arena_alloc
    test rax, rax
    jz .oom

    mov qword [rbx + Map.entries], rax
    mov qword [rbx + Map.capacity], r13
    mov qword [rbx + Map.mask], r13
    dec qword [rbx + Map.mask]
    mov qword [rbx + Map.count], 0
    mov qword [rbx + Map.arena], r12
    xor rax, rax
    ret
.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; map_put
;   Insert or update key-value pair
;   IN:  rdi = map, rsi = key ptr, rdx = key len, rcx = value ptr
;   OUT: rax = 0 OK, ENOMEM if full
; ---------------------------------------------------------------------------
global map_put
map_put:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi        ; map
    mov r12, rsi        ; key
    mov r13, rdx        ; key len
    mov r14, rcx        ; value
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r14

    mov rdi, r12
    mov rsi, r13
    call fnv1a_hash
    mov r15, rax        ; hash

    mov rdi, rbx
    mov rsi, r15
    call map_find_slot
    ; rax = slot index, rdx = 0 if empty, 1 if occupied

    test rdx, rdx
    jz .insert_new

    ; Key exists, update value
    mov rdi, [rbx + Map.entries]
    lea rdi, [rdi + rax * 16]
    mov qword [rdi + 8], r14
    xor rax, rax
    ret

.insert_new:
    ; Check load factor (> 75%)
    mov rax, [rbx + Map.count]
    inc rax
    mov rcx, [rbx + Map.capacity]
    lea rdx, [rcx * 3]
    shr rdx, 2
    cmp rax, rdx
    ja .resize

    ; Insert
    mov rdi, [rbx + Map.entries]
    lea rdi, [rdi + rax * 16]
    mov qword [rdi], r12
    mov qword [rdi + 8], r14
    inc qword [rbx + Map.count]
    xor rax, rax
    ret

.resize:
    ; TODO: Implement resize
    RETURN_ERROR ENOSPC

; ---------------------------------------------------------------------------
; map_get
;   Lookup value by key
;   IN:  rdi = map, rsi = key ptr, rdx = key len
;   OUT: rax = value ptr, 0 if not found
; ---------------------------------------------------------------------------
global map_get
map_get:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi        ; map
    mov r12, rsi        ; key
    mov r13, rdx        ; key len
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, r12
    mov rsi, r13
    call fnv1a_hash
    mov r14, rax

    mov rdi, rbx
    mov rsi, r14
    call map_find_slot
    test rdx, rdx
    jz .not_found

    mov rdi, [rbx + Map.entries]
    lea rdi, [rdi + rax * 16]
    mov rax, [rdi + 8]
    ret

.not_found:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; map_remove
;   Remove key-value pair
;   IN:  rdi = map, rsi = key ptr, rdx = key len
;   OUT: rax = 0 OK, ENOENT if not found
; ---------------------------------------------------------------------------
global map_remove
map_remove:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, r12
    mov rsi, r13
    call fnv1a_hash
    mov r14, rax

    mov rdi, rbx
    mov rsi, r14
    call map_find_slot
    test rdx, rdx
    jz .not_found

    ; Mark as deleted (key = -1)
    mov rdi, [rbx + Map.entries]
    lea rdi, [rdi + rax * 16]
    mov qword [rdi], -1
    dec qword [rbx + Map.count]
    xor rax, rax
    ret

.not_found:
    RETURN_ERROR ENOENT

; ---------------------------------------------------------------------------
; map_find_slot (internal)
;   IN:  rdi = map, rsi = hash
;   OUT: rax = slot index, rdx = 0 empty, 1 occupied
; ---------------------------------------------------------------------------
map_find_slot:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi        ; hash
    mov r13, [rbx + Map.mask]
    mov r14, [rbx + Map.entries]

    mov rax, r12
    and rax, r13        ; initial index

.loop:
    mov rdi, [r14 + rax * 16]
    test rdi, rdi
    jz .empty
    cmp rdi, -1
    je .next            ; deleted slot, continue
    ; Compare keys (simplified - assumes same pointer)
    ; In real implementation, would compare key data
    mov rdx, 1
    ret
.next:
    inc rax
    and rax, r13
    jmp .loop

.empty:
    xor rdx, rdx
    ret

; ---------------------------------------------------------------------------
; FNV-1a Hash (64-bit)
;   IN:  rdi = data ptr, rsi = length
;   OUT: rax = hash
; ---------------------------------------------------------------------------
global fnv1a_hash
fnv1a_hash:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov rax, 0xcbf29ce484222325  ; FNV offset basis
    mov r13, 0x100000001b3      ; FNV prime
    test r12, r12
    jz .done
.loop:
    movzx rdi, byte [rbx]
    xor rax, rdi
    mul r13
    inc rbx
    dec r12
    jnz .loop
.done:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; map_count
;   Get number of entries
;   IN:  rdi = map
;   OUT: rax = count
; ---------------------------------------------------------------------------
global map_count
map_count:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Map.count]
    ret

; ---------------------------------------------------------------------------
; map_clear
;   Clear all entries (keep capacity)
;   IN:  rdi = map
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global map_clear
map_clear:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + Map.entries]
    mov r13, [rbx + Map.capacity]
    test r13, r13
    jz .done
    xor rax, rax
    mov rcx, r13
.clear_loop:
    mov qword [r12], 0
    mov qword [r12 + 8], 0
    add r12, 16
    dec rcx
    jnz .clear_loop
.done:
    mov qword [rbx + Map.count], 0
    xor rax, rax
    ret

section .data

%define Map_entries   0
%define Map_capacity  8
%define Map_mask      16
%define Map_count     24
%define Map_arena     32
%define Map_size      40

global map_version
map_version: dq 0x010000