; ============================================================================
; Unit Test — Server Regions (src/server/regions/regions.asm over ugfx regions)
; ============================================================================
; test_region_suite -> eax = failed cases (each case returns 0 / 1).
; Regions are lists of x/y/w/h rectangles; how a subtraction splits them is
; the region code's business, so cases compare the total area and the count
; only where it is fixed.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"

extern arena_init
extern regions_init
extern regions_create
extern regions_destroy
extern regions_add
extern regions_subtract
extern regions_clear
extern regions_get_rects

%define HEAP_SIZE 65536

section .text

global test_region_suite
global test_region_main
test_region_suite:
test_region_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call fresh
    call %1
    add ebx, eax
%endmacro
    CASE tr_add_one
    CASE tr_empty_rect
    CASE tr_add_two
    CASE tr_subtract
    CASE tr_clear
    CASE tr_destroy
    CASE tr_bad_handle
    mov eax, ebx
    pop rbx
    ret

%macro PASS 0
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret
%endmacro

; regions_add / regions_subtract on the region in [handle]
%macro RECT 5
    lea rdi, [rel server]
    mov esi, [rel handle]
    mov edx, %2
    mov ecx, %3
    mov r8d, %4
    mov r9d, %5
    call regions_%1
%endmacro

; a new arena, region table and one region in [handle]
fresh:
    sub rsp, 8
    lea rdi, [rel arena]
    lea rsi, [rel heap]
    mov edx, HEAP_SIZE
    call arena_init
    lea rax, [rel arena]
    mov [rel server + Server.arena], rax
    lea rdi, [rel server]
    lea rsi, [rel arena]
    call regions_init
    lea rdi, [rel server]
    lea rsi, [rel arena]                ; any client pointer
    call regions_create
    mov [rel handle], eax
    add rsp, 8
    ret

; -> rax = rectangles in the region, rdx = their total area (negative: error)
measure:
    sub rsp, 24
    lea rdi, [rel server]
    mov esi, [rel handle]
    lea rdx, [rsp]
    lea rcx, [rsp + 8]
    call regions_get_rects
    test rax, rax
    js .out
    mov rax, [rsp + 8]
    mov r8, [rsp]
    xor edx, edx
    xor ecx, ecx
.next:
    cmp rcx, rax
    jae .out
    mov r9d, [r8 + 8]
    imul r9d, [r8 + 12]
    add rdx, r9
    add r8, 16
    inc rcx
    jmp .next
.out:
    add rsp, 24
    ret

tr_add_one:
    sub rsp, 8
    RECT add, 3, 4, 10, 20
    test rax, rax
    js .fail
    call measure
    cmp rax, 1
    jne .fail
    cmp rdx, 200
    jne .fail
    PASS

tr_empty_rect:
    sub rsp, 8
    RECT add, 0, 0, 0, 20               ; no width: nothing added
    RECT add, 0, 0, 20, 0
    call measure
    test rax, rax
    jnz .fail
    PASS

tr_add_two:
    sub rsp, 8
    RECT add, 0, 0, 10, 10
    RECT add, 20, 20, 5, 5
    call measure
    cmp rdx, 125
    jne .fail
    PASS

tr_subtract:
    sub rsp, 8
    RECT add, 0, 0, 10, 10
    RECT subtract, 0, 0, 5, 10          ; the left half
    test rax, rax
    js .fail
    call measure
    cmp rdx, 50
    jne .fail
    RECT subtract, 6, 2, 2, 2           ; a hole in what is left
    call measure
    cmp rdx, 46
    jne .fail
    PASS

tr_clear:
    sub rsp, 8
    RECT add, 0, 0, 10, 10
    lea rdi, [rel server]
    mov esi, [rel handle]
    call regions_clear
    test rax, rax
    jnz .fail
    call measure
    test rax, rax
    jnz .fail
    PASS

tr_destroy:
    sub rsp, 8
    lea rdi, [rel server]
    mov esi, [rel handle]
    call regions_destroy
    test rax, rax
    jnz .fail
    RECT add, 0, 0, 1, 1                ; the handle is dead
    cmp rax, -(ENOENT)
    jne .fail
    PASS

tr_bad_handle:
    sub rsp, 8
    add dword [rel handle], 1           ; another index
    RECT subtract, 0, 0, 1, 1
    cmp rax, -(ENOENT)
    jne .fail
    PASS


section .bss
alignb 16
server:     resb Server_size
arena:      resb Arena_size
handle:     resd 1
alignb 16
heap:       resb HEAP_SIZE
