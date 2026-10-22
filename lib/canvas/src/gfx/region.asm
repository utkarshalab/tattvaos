; Region operations -- arena-backed lists of 16-byte x/y/w/h rectangles.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern memcopy
extern rect_intersect

%define RECT_BYTES 16
%define REGION_INITIAL_CAPACITY 8

section .text

; IN: rdi = arena*. OUT: rax = Region*, or 0 on OOM.
global region_init
region_init:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov rsi, Region_SIZE
    call arena_alloc
    test rax, rax
    jz .done
    mov qword [rax + Region.rects], 0
    mov qword [rax + Region.count], 0
    mov qword [rax + Region.capacity], 0
    mov [rax + Region.arena], rbx
.done:
    EPILOGUE_RESTORE rbx
    ret

; Arena allocations have region lifetime; clearing ownership prevents reuse.
global region_destroy
region_destroy:
    PROLOGUE
    test rdi, rdi
    jz .done
    mov qword [rdi + Region.rects], 0
    mov qword [rdi + Region.count], 0
    mov qword [rdi + Region.capacity], 0
.done:
    xor eax, eax
    leave
    ret

global region_clear
region_clear:
    PROLOGUE
    test rdi, rdi
    jz .invalid
    mov qword [rdi + Region.count], 0
    xor eax, eax
    leave
    ret
.invalid:
    mov rax, -(EINVAL)
    leave
    ret

; Ensure capacity for at least rsi rectangles.
; IN rdi=region, rsi=needed. OUT 0 or negative errno.
region_reserve:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + Region.capacity]
    cmp r13, r12
    jae .ok
    test r13, r13
    jnz .grow
    mov r13, REGION_INITIAL_CAPACITY
.grow:
    cmp r13, r12
    jae .allocate
    shl r13, 1
    jc .oom
    jmp .grow
.allocate:
    mov rdi, [rbx + Region.arena]
    mov rsi, r13
    shl rsi, 4
    call arena_alloc
    test rax, rax
    jz .oom
    mov r14, rax
    mov rsi, [rbx + Region.rects]
    test rsi, rsi
    jz .install
    mov rdi, r14
    mov rdx, [rbx + Region.count]
    shl rdx, 4
    call memcopy
.install:
    mov [rbx + Region.rects], r14
    mov [rbx + Region.capacity], r13
.ok:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; IN rdi=region*, rsi=rect*.
global region_add_rect
region_add_rect:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jz .invalid
    test r12, r12
    jz .invalid
    cmp dword [r12 + 8], 0
    jle .ok
    cmp dword [r12 + 12], 0
    jle .ok
    mov r13, [rbx + Region.count]
    lea rsi, [r13 + 1]
    mov rdi, rbx
    call region_reserve
    test rax, rax
    js .out
    mov rdi, [rbx + Region.rects]
    mov rax, r13
    shl rax, 4
    add rdi, rax
    mov rsi, r12
    mov rdx, RECT_BYTES
    call memcopy
    inc qword [rbx + Region.count]
.ok:
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.invalid:
    mov rax, -(EINVAL)
    jmp .out

; IN rdi=region*, rsi=x, rdx=y. OUT 1/0.
global region_contains_point
region_contains_point:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    test rbx, rbx
    jz .no
    mov r14, [rbx + Region.count]
    mov rbx, [rbx + Region.rects]
.loop:
    test r14, r14
    jz .no
    cmp r12d, [rbx]
    jl .next
    mov eax, [rbx]
    add eax, [rbx + 8]
    cmp r12d, eax
    jge .next
    cmp r13d, [rbx + 4]
    jl .next
    mov eax, [rbx + 4]
    add eax, [rbx + 12]
    cmp r13d, eax
    jl .yes
.next:
    add rbx, RECT_BYTES
    dec r14
    jmp .loop
.yes:
    mov eax, 1
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.no:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

global region_is_empty
region_is_empty:
    xor eax, eax
    test rdi, rdi
    jz .yes
    cmp qword [rdi + Region.count], 0
    jne .done
.yes:
    mov eax, 1
.done:
    ret

; IN rdi=destination, rsi=source. Appends all source rectangles.
global region_union
region_union:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jz .invalid
    test r12, r12
    jz .invalid
    cmp rbx, r12
    je .ok
    mov r13, [r12 + Region.count]
    mov r14, [r12 + Region.rects]
.loop:
    test r13, r13
    jz .ok
    mov rdi, rbx
    mov rsi, r14
    call region_add_rect
    test rax, rax
    js .out
    add r14, RECT_BYTES
    dec r13
    jmp .loop
.ok:
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.invalid:
    mov rax, -(EINVAL)
    jmp .out

; IN rdi=destination, rsi=source. Replaces destination contents.
global region_copy
region_copy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jz .invalid
    test r12, r12
    jz .invalid
    cmp rbx, r12
    je .ok
    mov qword [rbx + Region.count], 0
    mov rdi, rbx
    mov rsi, r12
    call region_union
    EPILOGUE_RESTORE rbx, r12
    ret
.ok:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12
    ret
.invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12
    ret

; Keep only intersections with the supplied rectangle.
global region_intersect_rect
region_intersect_rect:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jz .invalid
    test r12, r12
    jz .invalid
    xor r13d, r13d
    xor r14d, r14d
    mov r15, [rbx + Region.count]
.loop:
    cmp r14, r15
    jae .finish
    mov rax, [rbx + Region.rects]
    mov rcx, r14
    shl rcx, 4
    add rax, rcx
    mov rdi, rsp
    mov rsi, rax
    mov rdx, r12
    call rect_intersect
    test rax, rax
    jnz .next
    mov rax, [rbx + Region.rects]
    mov rcx, r13
    shl rcx, 4
    lea rdi, [rax + rcx]
    mov rsi, rsp
    mov rdx, RECT_BYTES
    call memcopy
    inc r13
.next:
    inc r14
    jmp .loop
.finish:
    mov [rbx + Region.count], r13
    xor eax, eax
    jmp .out
.invalid:
    mov rax, -(EINVAL)
.out:
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; Subtract one rectangle, splitting each overlap into up to four strips.
global region_subtract_rect
region_subtract_rect:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 48
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jz .invalid
    test r12, r12
    jz .invalid
    mov r13, [rbx + Region.count]
    test r13, r13
    jz .ok
    lea rsi, [r13 * 4]
    mov rdi, [rbx + Region.arena]
    shl rsi, 4
    call arena_alloc
    test rax, rax
    jz .oom
    mov r14, rax                 ; destination array
    xor r15d, r15d               ; destination count
    xor ecx, ecx                 ; source index
.source_loop:
    cmp rcx, r13
    jae .install
    mov rax, [rbx + Region.rects]
    mov rdx, rcx
    shl rdx, 4
    add rax, rdx                 ; source rect
    mov [rsp + 32], rcx
    mov [rsp + 40], rax
    mov rdi, rsp                 ; intersection scratch
    mov rsi, rax
    mov rdx, r12
    call rect_intersect
    mov rcx, [rsp + 32]
    test rax, rax
    jz .split
    mov rsi, [rsp + 40]
    call .append
    jmp .source_next
.split:
    mov r10, [rsp + 40]
    ; top: source.x, source.y, source.w, intersection.y-source.y
    mov eax, [r10]
    mov [rsp + 16], eax
    mov eax, [r10 + 4]
    mov [rsp + 20], eax
    mov eax, [r10 + 8]
    mov [rsp + 24], eax
    mov eax, [rsp + 4]
    sub eax, [r10 + 4]
    mov [rsp + 28], eax
    lea rsi, [rsp + 16]
    call .append_nonempty
    ; bottom
    mov r10, [rsp + 40]
    mov eax, [r10]
    mov [rsp + 16], eax
    mov eax, [rsp + 4]
    add eax, [rsp + 12]
    mov [rsp + 20], eax
    mov eax, [r10 + 8]
    mov [rsp + 24], eax
    mov edx, [r10 + 4]
    add edx, [r10 + 12]
    sub edx, eax
    mov [rsp + 28], edx
    lea rsi, [rsp + 16]
    call .append_nonempty
    ; left and right strips span the intersection height
    mov r10, [rsp + 40]
    mov eax, [r10]
    mov [rsp + 16], eax
    mov eax, [rsp + 4]
    mov [rsp + 20], eax
    mov eax, [rsp]
    sub eax, [r10]
    mov [rsp + 24], eax
    mov eax, [rsp + 12]
    mov [rsp + 28], eax
    lea rsi, [rsp + 16]
    call .append_nonempty
    mov r10, [rsp + 40]
    mov eax, [rsp]
    add eax, [rsp + 8]
    mov [rsp + 16], eax
    mov eax, [rsp + 4]
    mov [rsp + 20], eax
    mov edx, [r10]
    add edx, [r10 + 8]
    sub edx, eax
    mov [rsp + 24], edx
    mov eax, [rsp + 12]
    mov [rsp + 28], eax
    lea rsi, [rsp + 16]
    call .append_nonempty
.source_next:
    mov rcx, [rsp + 32]
    inc rcx
    jmp .source_loop
.append_nonempty:
    cmp dword [rsi + 8], 0
    jle .append_ret
    cmp dword [rsi + 12], 0
    jle .append_ret
.append:
    mov rdi, r14
    mov rax, r15
    shl rax, 4
    add rdi, rax
    mov rdx, RECT_BYTES
    call memcopy
    inc r15
.append_ret:
    ret
.install:
    mov [rbx + Region.rects], r14
    mov [rbx + Region.count], r15
    lea rax, [r13 * 4]
    mov [rbx + Region.capacity], rax
.ok:
    xor eax, eax
    jmp .out
.oom:
    mov rax, -(ENOMEM)
    jmp .out
.invalid:
    mov rax, -(EINVAL)
.out:
    add rsp, 48
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global region_version
region_version: dq 0x010100
