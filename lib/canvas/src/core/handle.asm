; ============================================================================
; Handle Table — Generation-Tagged Handles (u32)
; 20-bit index, 12-bit generation = 1M objects, 4096 wraps
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern arena_alloc

; struct offsets (hoisted above use)
%define HandleTable_entries    0
%define HandleTable.entries 0
%define HandleTable_capacity   8
%define HandleTable.capacity 8
%define HandleTable_mask       16
%define HandleTable.mask 16
%define HandleTable_count      24
%define HandleTable.count 24
%define HandleTable_next_index 32
%define HandleTable.next_index 32
%define HandleTable_arena      40
%define HandleTable.arena 40
%define HandleTable_size       48

section .text

; ---------------------------------------------------------------------------
; handle_table_init
;   Initialize handle table
;   IN:  rdi = table pointer (HandleTable*)
;        rsi = arena
;        rdx = capacity (power of 2, max 1M)
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global handle_table_init
handle_table_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    test r13, r13
    jnz .check_pow2
    mov r13, 1024
.check_pow2:
    cmp r13, 1048576
    jbe .ok
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.ok:
    mov rax, r13
    dec rax
    test rax, r13
    jz .pow2_ok
    bsr rax, r13
    inc rax
    mov rcx, rax
    mov r13, 1
    shl r13, cl
.pow2_ok:

    ; Allocate entries array (16 bytes each: obj_ptr + generation)
    mov rdi, r12
    mov rsi, r13
    shl rsi, 4
    call arena_alloc
    test rax, rax
    jz .oom

    mov qword [rbx + HandleTable.entries], rax
    mov qword [rbx + HandleTable.capacity], r13
    mov qword [rbx + HandleTable.mask], r13
    dec qword [rbx + HandleTable.mask]
    mov qword [rbx + HandleTable.count], 0
    mov qword [rbx + HandleTable.next_index], 0
    mov qword [rbx + HandleTable.arena], r12
    ; Clear entries
    mov rdi, rax
    mov rcx, r13
    xor rax, rax
.clear_loop:
    mov qword [rdi], 0
    mov qword [rdi + 8], 0
    add rdi, 16
    dec rcx
    jnz .clear_loop
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; handle_create
;   Create new handle for object
;   IN:  rdi = table, rsi = object_ptr
;   OUT: rax = handle (u32), 0 on failure
; ---------------------------------------------------------------------------
global handle_create
handle_create:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + HandleTable.count]
    mov rcx, [rbx + HandleTable.capacity]
    cmp rax, rcx
    jae .full

    ; Find free slot (linear scan from last used)
    mov r13, [rbx + HandleTable.entries]
    mov r14, [rbx + HandleTable.mask]
    mov rax, [rbx + HandleTable.next_index]
    and rax, r14

.find_loop:
    mov r15, rax
    shl r15, 4                  ; multiply by 16
    mov rcx, [r13 + r15]        ; obj_ptr
    test rcx, rcx
    jz .found
    inc rax
    and rax, r14
    cmp rax, [rbx + HandleTable.next_index]
    jne .find_loop
    ; Should not happen if count < capacity
    jmp .full

.found:
    ; Get generation
    mov r15, rax
    shl r15, 4                  ; multiply by 16
    mov rcx, [r13 + r15 + 8]
    inc ecx
    and ecx, 0xFFF            ; 12-bit generation
    mov [r13 + r15], r12       ; obj_ptr
    mov [r13 + r15 + 8], rcx

    ; Build handle: (generation << 20) | index
    shl rcx, 20
    or ecx, eax
    mov edx, ecx

    ; Update next_index and count
    mov eax, edx
    and eax, 0xFFFFF
    inc rax
    and eax, r14d
    mov [rbx + HandleTable.next_index], eax
    inc qword [rbx + HandleTable.count]
    mov eax, edx
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.full:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; handle_resolve
;   Resolve handle to object pointer
;   IN:  rdi = table, rsi = handle (u32)
;   OUT: rax = object_ptr, 0 if invalid
; ---------------------------------------------------------------------------
global handle_resolve
handle_resolve:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov eax, r12d
    and eax, 0xFFFFF          ; 20-bit index
    mov ecx, r12d
    shr ecx, 20               ; 12-bit generation
    and ecx, 0xFFF

    cmp eax, [rbx + HandleTable.capacity]
    jae .invalid

    mov rbx, [rbx + HandleTable.entries]
    mov r15, rax
    shl r15, 4
    mov rdx, [rbx + r15 + 8]  ; stored generation
    cmp edx, ecx
    jne .invalid

    mov r15, rax
    shl r15, 4
    mov rax, [rbx + r15]      ; obj_ptr
    EPILOGUE_RESTORE rbx, r12
    ret

.invalid:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; handle_destroy
;   Destroy handle (mark slot free)
;   IN:  rdi = table, rsi = handle
;   OUT: rax = 0 OK, EINVAL if invalid
; ---------------------------------------------------------------------------
global handle_destroy
handle_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov eax, r12d
    and eax, 0xFFFFF
    mov ecx, r12d
    shr ecx, 20
    and ecx, 0xFFF

    cmp eax, [rbx + HandleTable.capacity]
    jae .invalid

    mov rbx, [rbx + HandleTable.entries]
    mov r15, rax
    shl r15, 4
    mov rdx, [rbx + r15 + 8]
    cmp edx, ecx
    jne .invalid

    mov r15, rax
    shl r15, 4
    mov qword [rbx + r15], 0
    dec qword [rbx + HandleTable.count]
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; handle_count
;   Get number of active handles
;   IN:  rdi = table
;   OUT: rax = count
; ---------------------------------------------------------------------------
global handle_count
handle_count:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + HandleTable.count]
    leave
    ret

; ---------------------------------------------------------------------------
; handle_table_clear
;   Clear all handles
;   IN:  rdi = table
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global handle_table_clear
handle_table_clear:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + HandleTable.entries]
    mov r13, [rbx + HandleTable.capacity]
    test r13, r13
    jz .done
    xor rax, rax
.clear_loop:
    mov qword [r12], 0
    mov qword [r12 + 8], 0
    add r12, 16
    dec r13
    jnz .clear_loop
.done:
    mov qword [rbx + HandleTable.count], 0
    mov qword [rbx + HandleTable.next_index], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data


global handle_version
handle_version: dq 0x010000
