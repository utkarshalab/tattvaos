%ifndef GUARD_STORAGE_UXFS_CLUSTER_ERASURE_ASM
%define GUARD_STORAGE_UXFS_CLUSTER_ERASURE_ASM
; =============================================================================
; Tattva OS — storage/uxfs/cluster/erasure.asm
; =============================================================================
; Reed-Solomon (k+m) Erasure Coding over GF(2^8).
;
; Implements:
;   - GF(2^8) arithmetic with log/antilog tables (`uxfs_erasure_init`,
;     `uxfs_erasure_gf_mul`, `uxfs_erasure_gf_inv`)
;   - Vandermonde generator matrix construction (`uxfs_erasure_build_matrix`)
;   - Parity generation across k data blocks (`uxfs_erasure_encode`)
;   - Lost-fragment recovery by matrix inversion (`uxfs_erasure_reconstruct`)
;
; Erasure coding stores k data fragments plus m parity fragments and survives
; the loss of any m of them. Compared with m-way replication it costs
; (k+m)/k storage instead of (m+1)x — 1.5x versus 3x for a typical 8+4 —
; for the same fault tolerance.
;
; Arithmetic is in GF(2^8) modulo x^8+x^4+x^3+x^2+1 (0x11D), where every
; non-zero element is invertible. That is what makes recovery possible: any k
; surviving fragments form a k-by-k submatrix that is guaranteed invertible,
; so the original data can always be solved for.
;
; Multiplication goes through log/antilog tables rather than the bitwise loop:
; a*b = antilog[log[a] + log[b]], turning eight iterations into two lookups and
; an add. The bitwise routine is retained for table construction and for
; callers that cannot depend on initialisation having run.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define UXFS_EC_FIELD_SIZE           256
%define UXFS_EC_POLY                 0x11D   ; x^8+x^4+x^3+x^2+1
%define UXFS_EC_GENERATOR            0x02    ; Primitive element
%define UXFS_EC_MAX_K                32      ; Data fragments
%define UXFS_EC_MAX_M                16      ; Parity fragments
%define UXFS_EC_MAX_SHARDS           (UXFS_EC_MAX_K + UXFS_EC_MAX_M)

section .data
align 64

; log[x] = i such that generator^i == x. log[0] is undefined and never read.
uxfs_ec_log:            times UXFS_EC_FIELD_SIZE db 0
; Doubled so a sum of two logs (max 508) indexes without a modulo.
uxfs_ec_exp:            times (UXFS_EC_FIELD_SIZE * 2) db 0

uxfs_ec_matrix:         times UXFS_EC_MAX_M * UXFS_EC_MAX_K db 0
uxfs_ec_solve:          times UXFS_EC_MAX_K * UXFS_EC_MAX_K db 0
uxfs_ec_invert:         times UXFS_EC_MAX_K * UXFS_EC_MAX_K db 0

; Maps each solve-matrix row back to the shard index that supplied it. The
; recovery multiply needs this to know which fragment each inverse column
; should be applied to.
uxfs_ec_rowmap:         times UXFS_EC_MAX_K db 0

global uxfs_ec_initialised
uxfs_ec_initialised:    dq 0

section .text

global uxfs_erasure_init
global uxfs_erasure_gf_mul
global uxfs_erasure_gf_mul_fast
global uxfs_erasure_gf_inv
global uxfs_erasure_build_matrix
global uxfs_erasure_encode
global uxfs_erasure_reconstruct
global uxfs_erasure_invert
global uxfs_ec_swap_rows
global uxfs_ec_solve_ptr
global uxfs_ec_inv_ptr

; -----------------------------------------------------------------------------
; uxfs_erasure_gf_mul
;
; Bitwise GF(2^8) multiply. Table-free, so it is usable before initialisation.
;
; Inputs:
;   DIL = Operand A
;   SIL = Operand B
;
; Returns:
;   AL = Product in GF(2^8)
; -----------------------------------------------------------------------------
align 32
uxfs_erasure_gf_mul:
    push rbx

    movzx eax, dil
    movzx ebx, sil
    xor ecx, ecx                    ; Accumulator

.gf_loop:
    test ebx, 1
    jz .no_add
    xor ecx, eax

.no_add:
    test eax, 0x80                  ; Will the shift overflow the field?
    jz .no_poly
    shl eax, 1
    xor eax, UXFS_EC_POLY           ; Reduce back into GF(2^8)
    jmp .next_bit

.no_poly:
    shl eax, 1

.next_bit:
    shr ebx, 1
    jnz .gf_loop

    mov al, cl
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_erasure_init
;
; Builds the log/antilog tables by walking the powers of the primitive element.
; Every non-zero field element appears exactly once across 255 steps.
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
uxfs_erasure_init:
    push rbx
    push r12
    push r13

    xor r12d, r12d                  ; Exponent
    mov r13d, 1                     ; Running power, generator^0 = 1

.ei_loop:
    cmp r12d, 255
    jae .ei_wrap

    lea rbx, [uxfs_ec_exp]
    mov byte [rbx + r12], r13b

    lea rbx, [uxfs_ec_log]
    movzx eax, r13b
    mov byte [rbx + rax], r12b

    ; power *= generator
    movzx edi, r13b
    mov esi, UXFS_EC_GENERATOR
    call uxfs_erasure_gf_mul
    movzx r13d, al

    inc r12d
    jmp .ei_loop

.ei_wrap:
    ; Mirror the table so log sums up to 508 index directly, with no modulo.
    xor r12d, r12d
.ei_mirror:
    cmp r12d, 255
    jae .ei_done
    lea rbx, [uxfs_ec_exp]
    mov al, byte [rbx + r12]
    mov byte [rbx + r12 + 255], al
    inc r12d
    jmp .ei_mirror

.ei_done:
    mov qword [uxfs_ec_initialised], 1
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_erasure_gf_mul_fast
;
; Table-driven multiply: a*b = antilog[log a + log b]. Zero is special-cased
; because it has no logarithm.
;
; Inputs:
;   DIL = Operand A
;   SIL = Operand B
;
; Returns:
;   AL = Product in GF(2^8)
; -----------------------------------------------------------------------------
align 32
uxfs_erasure_gf_mul_fast:
    test dil, dil
    jz .mf_zero
    test sil, sil
    jz .mf_zero

    push rbx
    lea rbx, [uxfs_ec_log]
    movzx eax, dil
    movzx eax, byte [rbx + rax]
    movzx ecx, sil
    movzx ecx, byte [rbx + rcx]
    add eax, ecx                    ; Sum of logs, at most 508

    lea rbx, [uxfs_ec_exp]
    movzx eax, byte [rbx + rax]     ; Mirrored table absorbs the wraparound
    pop rbx
    ret

.mf_zero:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; uxfs_erasure_gf_inv
;
; Multiplicative inverse: antilog[255 - log a].
;
; Inputs:
;   DIL = Operand A (must be non-zero)
;
; Returns:
;   AL = Inverse, or 0 when the input was 0
; -----------------------------------------------------------------------------
align 32
uxfs_erasure_gf_inv:
    test dil, dil
    jz .gi_zero

    push rbx
    lea rbx, [uxfs_ec_log]
    movzx eax, dil
    movzx eax, byte [rbx + rax]
    mov ecx, 255
    sub ecx, eax

    lea rbx, [uxfs_ec_exp]
    movzx eax, byte [rbx + rcx]
    pop rbx
    ret

.gi_zero:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; uxfs_erasure_build_matrix
;
; Builds an m-by-k Vandermonde generator matrix, entry[i][j] = (i+1)^j.
;
; Any k rows drawn from the combined identity-plus-generator matrix are
; linearly independent, which is exactly the property that guarantees recovery
; from any m losses.
;
; Inputs:
;   EDI = k, data fragment count
;   ESI = m, parity fragment count
;
; Returns:
;   EAX = 0 on success, POSIX_EINVAL when the geometry is out of range
; -----------------------------------------------------------------------------
align 32
uxfs_erasure_build_matrix:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12d, edi                   ; k
    mov r13d, esi                   ; m

    test r12d, r12d
    jz .bm_inval
    cmp r12d, UXFS_EC_MAX_K
    ja .bm_inval
    test r13d, r13d
    jz .bm_inval
    cmp r13d, UXFS_EC_MAX_M
    ja .bm_inval

    cmp qword [uxfs_ec_initialised], 0
    jne .bm_ready
    call uxfs_erasure_init

.bm_ready:
    xor r14d, r14d                  ; Row index i

.bm_row:
    cmp r14d, r13d
    jae .bm_done

    xor r15d, r15d                  ; Column index j
    mov ebx, 1                      ; Running (i+1)^j, starting at j = 0

.bm_col:
    cmp r15d, r12d
    jae .bm_next_row

    ; matrix[i][j] = (i+1)^j
    mov eax, r14d
    imul eax, r12d
    add eax, r15d
    lea rcx, [uxfs_ec_matrix]
    mov byte [rcx + rax], bl

    ; Advance the power: multiply by (i+1).
    movzx edi, bl
    mov esi, r14d
    inc esi
    call uxfs_erasure_gf_mul_fast
    movzx ebx, al

    inc r15d
    jmp .bm_col

.bm_next_row:
    inc r14d
    jmp .bm_row

.bm_done:
    xor eax, eax
    jmp .bm_return

.bm_inval:
    mov eax, POSIX_EINVAL

.bm_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_erasure_encode
;
; Generates m parity fragments from k data fragments.
;
;   parity[i] = XOR over j of ( matrix[i][j] * data[j] )
;
; Inputs:
;   RDI = Pointer to an array of k data fragment pointers
;   RSI = Pointer to an array of m parity fragment pointers
;   EDX = k
;   ECX = m
;   R8D = Fragment length in bytes
;
; Returns:
;   EAX = 0 on success, POSIX_EINVAL on bad geometry
; -----------------------------------------------------------------------------
align 32
uxfs_erasure_encode:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 48

    mov [rsp], rdi                  ; Data pointer array
    mov [rsp + 8], rsi              ; Parity pointer array
    mov [rsp + 16], rdx             ; k
    mov [rsp + 24], rcx             ; m
    mov [rsp + 32], r8              ; Fragment length

    test rdi, rdi
    jz .ee_inval
    test rsi, rsi
    jz .ee_inval
    test edx, edx
    jz .ee_inval
    test r8d, r8d
    jz .ee_inval

    mov edi, edx
    mov esi, ecx
    call uxfs_erasure_build_matrix
    test eax, eax
    jnz .ee_return

    xor r12d, r12d                  ; Parity row i

.ee_row:
    mov rax, [rsp + 24]
    cmp r12d, eax
    jae .ee_done

    ; Zero this parity fragment before accumulating into it.
    mov rax, [rsp + 8]
    mov rdi, [rax + r12 * 8]
    mov rcx, [rsp + 32]
    xor al, al
    rep stosb

    xor r13d, r13d                  ; Data column j

.ee_col:
    mov rax, [rsp + 16]
    cmp r13d, eax
    jae .ee_next_row

    ; coefficient = matrix[i][j]
    mov eax, r12d
    mov rcx, [rsp + 16]
    imul eax, ecx
    add eax, r13d
    lea rcx, [uxfs_ec_matrix]
    movzx r14d, byte [rcx + rax]

    test r14d, r14d
    jz .ee_next_col                 ; Multiplying by zero contributes nothing

    mov rax, [rsp]
    mov r15, [rax + r13 * 8]        ; Source fragment
    mov rax, [rsp + 8]
    mov rbx, [rax + r12 * 8]        ; Destination parity

    xor rcx, rcx

.ee_byte:
    cmp rcx, [rsp + 32]
    jae .ee_next_col

    movzx edi, byte [r15 + rcx]
    mov esi, r14d
    push rcx
    call uxfs_erasure_gf_mul_fast
    pop rcx

    xor byte [rbx + rcx], al        ; Accumulate in GF(2): addition is XOR

    inc rcx
    jmp .ee_byte

.ee_next_col:
    inc r13d
    jmp .ee_col

.ee_next_row:
    inc r12d
    jmp .ee_row

.ee_done:
    xor eax, eax
    jmp .ee_return

.ee_inval:
    mov eax, POSIX_EINVAL

.ee_return:
    add rsp, 48
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_ec_solve_ptr
;
; Address of solve[row][col].
;
; Inputs:
;   RDI = Row, RSI = Column, RDX = k
;
; Returns:
;   RAX = Element address
; -----------------------------------------------------------------------------
align 32
uxfs_ec_solve_ptr:
    mov rax, rdi
    imul rax, rdx
    add rax, rsi
    lea rcx, [uxfs_ec_solve]
    add rax, rcx
    ret

; -----------------------------------------------------------------------------
; uxfs_ec_inv_ptr
;
; Address of invert[row][col].
;
; Inputs:
;   RDI = Row, RSI = Column, RDX = k
;
; Returns:
;   RAX = Element address
; -----------------------------------------------------------------------------
align 32
uxfs_ec_inv_ptr:
    mov rax, rdi
    imul rax, rdx
    add rax, rsi
    lea rcx, [uxfs_ec_invert]
    add rax, rcx
    ret

; -----------------------------------------------------------------------------
; uxfs_ec_swap_rows
;
; Exchanges two rows of the solve matrix and the in-progress inverse.
;
; The ROW MAP IS DELIBERATELY NOT SWAPPED. A row swap is itself one of the
; elementary operations accumulating into the augmented side: starting from
; [M | I], every operation left-multiplies both halves, so when the left side
; reaches I the right side holds M-inverse for the ORIGINAL row order. The
; recovery multiply therefore indexes survivors in build order, and permuting
; the map as well would apply the permutation a second time — which silently
; pairs every coefficient with the wrong fragment.
;
; Inputs:
;   RDI = Row A, RSI = Row B, RDX = k
; -----------------------------------------------------------------------------
align 32
uxfs_ec_swap_rows:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; Row A
    mov r13, rsi                    ; Row B
    mov r14, rdx                    ; k

    cmp r12, r13
    je .sr_done                     ; Nothing to do

    xor r15, r15                    ; Column

.sr_col:
    cmp r15, r14
    jae .sr_map

    ; --- solve ---
    mov rdi, r12
    mov rsi, r15
    mov rdx, r14
    call uxfs_ec_solve_ptr
    mov rbx, rax                    ; &solve[A][c]

    mov rdi, r13
    mov rsi, r15
    mov rdx, r14
    call uxfs_ec_solve_ptr

    mov cl, byte [rbx]
    mov dl, byte [rax]
    mov byte [rbx], dl
    mov byte [rax], cl

    ; --- invert ---
    mov rdi, r12
    mov rsi, r15
    mov rdx, r14
    call uxfs_ec_inv_ptr
    mov rbx, rax

    mov rdi, r13
    mov rsi, r15
    mov rdx, r14
    call uxfs_ec_inv_ptr

    mov cl, byte [rbx]
    mov dl, byte [rax]
    mov byte [rbx], dl
    mov byte [rax], cl

    inc r15
    jmp .sr_col

.sr_map:
    ; Intentionally empty: see the note above on why the row map stays put.

.sr_done:
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_erasure_invert
;
; Gauss-Jordan inversion of the k-by-k solve matrix into uxfs_ec_invert.
;
; Seeds the inverse as the identity, then reduces solve to the identity while
; applying every operation to both. Whatever turns solve into I turns I into
; solve's inverse.
;
; Partial pivoting is mandatory here, not an optimisation. Surviving data
; shards contribute identity rows, so a zero on the diagonal is the COMMON
; case; without a row swap the elimination would declare a perfectly
; invertible matrix singular.
;
; Inputs:
;   EDI = k
;
; Returns:
;   EAX = 0 on success, POSIX_EIO when the matrix is genuinely singular
; -----------------------------------------------------------------------------
align 32
uxfs_erasure_invert:
    push rbx
    push r12
    push r13
    push r14
    push r15

    movzx rbx, di                   ; RBX = k, held in a register throughout
    test rbx, rbx
    jz .iv_singular
    cmp rbx, UXFS_EC_MAX_K
    ja .iv_singular

    ; ---- Seed the inverse as the identity ----
    xor r12, r12
.iv_seed_row:
    cmp r12, rbx
    jae .iv_seeded
    xor r13, r13
.iv_seed_col:
    cmp r13, rbx
    jae .iv_seed_next

    mov rdi, r12
    mov rsi, r13
    mov rdx, rbx
    call uxfs_ec_inv_ptr

    mov byte [rax], 0
    cmp r12, r13
    jne .iv_seed_skip
    mov byte [rax], 1
.iv_seed_skip:
    inc r13
    jmp .iv_seed_col
.iv_seed_next:
    inc r12
    jmp .iv_seed_row

.iv_seeded:
    xor r12, r12                    ; R12 = pivot index

.iv_pivot:
    cmp r12, rbx
    jae .iv_ok

    ; ---- Ensure a non-zero pivot, swapping a lower row up if needed ----
    mov rdi, r12
    mov rsi, r12
    mov rdx, rbx
    call uxfs_ec_solve_ptr
    movzx r14d, byte [rax]
    test r14d, r14d
    jnz .iv_have_pivot

    mov r13, r12
    inc r13
.iv_find:
    cmp r13, rbx
    jae .iv_singular                ; No row below has a usable pivot

    mov rdi, r13
    mov rsi, r12
    mov rdx, rbx
    call uxfs_ec_solve_ptr
    cmp byte [rax], 0
    jne .iv_do_swap

    inc r13
    jmp .iv_find

.iv_do_swap:
    mov rdi, r12
    mov rsi, r13
    mov rdx, rbx
    call uxfs_ec_swap_rows

    mov rdi, r12
    mov rsi, r12
    mov rdx, rbx
    call uxfs_ec_solve_ptr
    movzx r14d, byte [rax]
    test r14d, r14d
    jz .iv_singular

.iv_have_pivot:
    ; ---- Scale the pivot row so solve[p][p] becomes 1 ----
    movzx edi, r14b
    call uxfs_erasure_gf_inv
    movzx r14d, al                  ; R14 = inverse of the pivot

    xor r15, r15
.iv_scale:
    cmp r15, rbx
    jae .iv_eliminate

    mov rdi, r12
    mov rsi, r15
    mov rdx, rbx
    call uxfs_ec_solve_ptr
    mov r13, rax                    ; Keep the address across the multiply
    movzx edi, byte [rax]
    mov esi, r14d
    call uxfs_erasure_gf_mul_fast
    mov byte [r13], al

    mov rdi, r12
    mov rsi, r15
    mov rdx, rbx
    call uxfs_ec_inv_ptr
    mov r13, rax
    movzx edi, byte [rax]
    mov esi, r14d
    call uxfs_erasure_gf_mul_fast
    mov byte [r13], al

    inc r15
    jmp .iv_scale

.iv_eliminate:
    ; ---- Clear this column from every other row ----
    push rbp
    xor rbp, rbp                    ; RBP = row being eliminated

.iv_elim_row:
    cmp rbp, rbx
    jae .iv_elim_done
    cmp rbp, r12
    je .iv_elim_next

    ; Factor = solve[row][pivot]. Cached before the row is modified, because
    ; the column loop overwrites that very element when it reaches it.
    mov rdi, rbp
    mov rsi, r12
    mov rdx, rbx
    call uxfs_ec_solve_ptr
    movzx r14d, byte [rax]
    test r14d, r14d
    jz .iv_elim_next                ; Already zero here

    xor r15, r15
.iv_elim_col:
    cmp r15, rbx
    jae .iv_elim_next

    ; solve[row][c] ^= factor * solve[pivot][c]
    mov rdi, r12
    mov rsi, r15
    mov rdx, rbx
    call uxfs_ec_solve_ptr
    movzx edi, byte [rax]
    mov esi, r14d
    call uxfs_erasure_gf_mul_fast
    mov r13d, eax                   ; Product

    mov rdi, rbp
    mov rsi, r15
    mov rdx, rbx
    call uxfs_ec_solve_ptr
    xor byte [rax], r13b

    ; invert[row][c] ^= factor * invert[pivot][c]
    mov rdi, r12
    mov rsi, r15
    mov rdx, rbx
    call uxfs_ec_inv_ptr
    movzx edi, byte [rax]
    mov esi, r14d
    call uxfs_erasure_gf_mul_fast
    mov r13d, eax

    mov rdi, rbp
    mov rsi, r15
    mov rdx, rbx
    call uxfs_ec_inv_ptr
    xor byte [rax], r13b

    inc r15
    jmp .iv_elim_col

.iv_elim_next:
    inc rbp
    jmp .iv_elim_row

.iv_elim_done:
    pop rbp
    inc r12
    jmp .iv_pivot

.iv_ok:
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.iv_singular:
    mov eax, POSIX_EIO
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_erasure_reconstruct
;
; Recovers lost data fragments from any k survivors.
;
; Shard s contributes row E[s] of the combined encoding matrix: an identity row
; when s is a data shard, the generator row when s is parity. Taking the k rows
; belonging to survivors gives M, with survivors = M * data, so data = M^-1 *
; survivors.
;
; The Vandermonde generator guarantees every such M is invertible, which is
; exactly why ANY m losses are survivable rather than only specific patterns.
;
; Inputs:
;   RDI = Pointer to an array of (k+m) fragment pointers. Entries for lost
;         shards must point at writable buffers to receive recovered data.
;   RSI = Pointer to a (k+m) byte availability map; non-zero means present
;   EDX = k
;   ECX = m
;   R8D = Fragment length in bytes
;
; Returns:
;   EAX = 0 on success
;         POSIX_EINVAL on bad geometry or a missing output buffer
;         POSIX_EIO    when fewer than k fragments survive, or M is singular
; -----------------------------------------------------------------------------
align 32
uxfs_erasure_reconstruct:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 64

    mov [rsp], rdi                  ; Fragment pointer array
    mov [rsp + 8], rsi              ; Availability map
    mov [rsp + 16], rdx             ; k
    mov [rsp + 24], rcx             ; m
    mov [rsp + 32], r8              ; Fragment length

    test rdi, rdi
    jz .rc_inval
    test rsi, rsi
    jz .rc_inval
    test edx, edx
    jz .rc_inval
    cmp edx, UXFS_EC_MAX_K
    ja .rc_inval
    test r8d, r8d
    jz .rc_inval

    mov rax, rdx
    add rax, rcx
    mov [rsp + 40], rax             ; Total shard count

    cmp qword [uxfs_ec_initialised], 0
    jne .rc_ready
    call uxfs_erasure_init

.rc_ready:
    mov edi, dword [rsp + 16]
    mov esi, dword [rsp + 24]
    call uxfs_erasure_build_matrix
    test eax, eax
    jnz .rc_return

    ; ---- Assemble the k-by-k solve matrix from the first k survivors ----
    xor r12, r12                    ; Shard index
    xor r14, r14                    ; Solve row

.rc_build:
    cmp r12, [rsp + 40]
    jae .rc_built
    cmp r14, [rsp + 16]
    jae .rc_built

    mov rax, [rsp + 8]
    cmp byte [rax + r12], 0
    je .rc_build_next               ; Lost shard contributes no row

    mov rbx, [rsp + 16]             ; k
    xor r15, r15                    ; Column

    cmp r12, rbx
    jae .rc_parity_row

    ; --- Data shard: identity row with a 1 in column r12 ---
.rc_id_col:
    cmp r15, rbx
    jae .rc_row_done

    mov rdi, r14
    mov rsi, r15
    mov rdx, rbx
    call uxfs_ec_solve_ptr

    mov byte [rax], 0
    cmp r15, r12
    jne .rc_id_next
    mov byte [rax], 1
.rc_id_next:
    inc r15
    jmp .rc_id_col

    ; --- Parity shard: copy its generator row ---
.rc_parity_row:
    mov rbp, r12
    sub rbp, rbx                    ; Parity index = shard - k

.rc_par_col:
    cmp r15, rbx
    jae .rc_row_done

    ; matrix[parity][col]
    mov rax, rbp
    imul rax, rbx
    add rax, r15
    lea rcx, [uxfs_ec_matrix]
    movzx r13d, byte [rcx + rax]

    mov rdi, r14
    mov rsi, r15
    mov rdx, rbx
    call uxfs_ec_solve_ptr
    mov byte [rax], r13b

    inc r15
    jmp .rc_par_col

.rc_row_done:
    ; Remember which shard fed this row.
    lea rax, [uxfs_ec_rowmap]
    mov byte [rax + r14], r12b
    inc r14

.rc_build_next:
    inc r12
    jmp .rc_build

.rc_built:
    ; Fewer than k rows means fewer than k survivors: the data is gone.
    cmp r14, [rsp + 16]
    jb .rc_unrecoverable

    mov edi, dword [rsp + 16]
    call uxfs_erasure_invert
    test eax, eax
    jnz .rc_unrecoverable

    ; ---- Recovery multiply ----
    ;   data[i] = XOR over j of ( invert[i][j] * survivor[rowmap[j]] )
    ; Parity shards are not regenerated here; re-run encode once data is whole.
    xor r12, r12                    ; Data shard index i

.rc_fix_row:
    cmp r12, [rsp + 16]
    jae .rc_fixed

    mov rax, [rsp + 8]
    cmp byte [rax + r12], 0
    jne .rc_fix_next                ; Survived; nothing to rebuild

    mov rax, [rsp]
    mov rdi, [rax + r12 * 8]
    test rdi, rdi
    jz .rc_inval                    ; No buffer supplied for a lost shard
    mov [rsp + 48], rdi

    mov rcx, [rsp + 32]
    xor al, al
    rep stosb                       ; Clear before accumulating

    xor r13, r13                    ; Inverse column j

.rc_fix_col:
    cmp r13, [rsp + 16]
    jae .rc_fix_next

    mov rdi, r12
    mov rsi, r13
    mov rdx, [rsp + 16]
    call uxfs_ec_inv_ptr
    movzx r14d, byte [rax]          ; Coefficient

    test r14d, r14d
    jz .rc_fix_col_next             ; Zero contributes nothing

    lea rax, [uxfs_ec_rowmap]
    movzx eax, byte [rax + r13]
    mov rcx, [rsp]
    mov r15, [rcx + rax * 8]        ; Survivor fragment

    mov rbx, [rsp + 48]             ; Destination
    xor rbp, rbp

.rc_fix_byte:
    cmp rbp, [rsp + 32]
    jae .rc_fix_col_next

    movzx edi, byte [r15 + rbp]
    mov esi, r14d
    call uxfs_erasure_gf_mul_fast

    xor byte [rbx + rbp], al        ; GF addition is XOR

    inc rbp
    jmp .rc_fix_byte

.rc_fix_col_next:
    inc r13
    jmp .rc_fix_col

.rc_fix_next:
    inc r12
    jmp .rc_fix_row

.rc_fixed:
    xor eax, eax
    jmp .rc_return

.rc_unrecoverable:
    mov eax, POSIX_EIO
    jmp .rc_return

.rc_inval:
    mov eax, POSIX_EINVAL

.rc_return:
    add rsp, 64
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_STORAGE_UXFS_CLUSTER_ERASURE_ASM
