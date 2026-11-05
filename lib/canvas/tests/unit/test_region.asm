; ============================================================================
; Unit Test — Server Regions (src/server/regions/regions.asm over ugfx regions)
; ============================================================================
; test_region_suite -> eax = failed cases (each case returns 0 / 1).
; Regions are lists of x/y/w/h rectangles; how a subtraction splits them is
; the region code's business, so cases compare the total area and the count
; only where it is fixed. Each region is its client's: another client's
; handle does not resolve, and a client going takes its regions with it.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"

extern arena_init
extern regions_init
extern regions_create
extern regions_destroy
extern regions_destroy_client
extern regions_own
extern regions_add
extern regions_subtract
extern regions_clear

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
    CASE tr_other_client
    CASE tr_client_gone
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

; regions_add / regions_subtract of (x, y, w, h) on the client's region in
; [handle] -> rax
%macro RECT 5
    mov dword [rel rect], %2
    mov dword [rel rect + 4], %3
    mov dword [rel rect + 8], %4
    mov dword [rel rect + 12], %5
    call own
    mov rdi, rax
    lea rsi, [rel rect]
    call regions_%1
%endmacro

; a new arena, region table, two clients, and one region of the first's in
; [handle]
fresh:
    sub rsp, 8
    lea rdi, [rel arena]
    lea rsi, [rel heap]
    mov edx, HEAP_SIZE
    call arena_init
    lea rax, [rel arena]
    mov [rel server + Server.arena], rax
    mov [rel client + Client.arena], rax
    mov [rel other + Client.arena], rax
    mov qword [rel client + Client.regions], 0
    mov qword [rel other + Client.regions], 0
    lea rdi, [rel server]
    lea rsi, [rel arena]
    call regions_init
    lea rdi, [rel server]
    lea rsi, [rel client]
    call regions_create
    mov [rel handle], eax
    add rsp, 8
    ret

; -> rax = the client's Region* for [handle], 0 if it has none
own:
    sub rsp, 8
    lea rdi, [rel server]
    lea rsi, [rel client]
    mov edx, [rel handle]
    call regions_own
    add rsp, 8
    ret

; -> rax = rectangles in the region, rdx = their total area
measure:
    sub rsp, 8
    call own
    add rsp, 8
    mov r8, [rax + Region.rects]
    mov rax, [rax + Region.count]
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
    call own
    mov rdi, rax
    call regions_clear
    call measure
    test rax, rax
    jnz .fail
    PASS

tr_destroy:
    sub rsp, 8
    lea rdi, [rel server]
    lea rsi, [rel client]
    mov edx, [rel handle]
    call regions_destroy
    test rax, rax
    jnz .fail
    call own                            ; the handle is dead
    test rax, rax
    jnz .fail
    cmp qword [rel client + Client.regions], 0
    jne .fail                           ; and off the client's list
    PASS

tr_bad_handle:
    sub rsp, 8
    add dword [rel handle], 1           ; another index
    call own
    test rax, rax
    jnz .fail
    PASS

; Another client's handle neither resolves nor destroys
tr_other_client:
    sub rsp, 8
    lea rdi, [rel server]
    lea rsi, [rel other]
    mov edx, [rel handle]
    call regions_own
    test rax, rax
    jnz .fail
    lea rdi, [rel server]
    lea rsi, [rel other]
    mov edx, [rel handle]
    call regions_destroy
    cmp rax, -(ENOENT)
    jne .fail
    call own                            ; still the owner's
    test rax, rax
    jz .fail
    PASS

; A client going takes its regions' handles with it
tr_client_gone:
    sub rsp, 8
    lea rdi, [rel server]
    lea rsi, [rel client]
    call regions_create
    lea rdi, [rel server]
    lea rsi, [rel client]
    call regions_destroy_client
    call own
    test rax, rax
    jnz .fail
    cmp qword [rel client + Client.regions], 0
    jne .fail
    PASS

section .bss
alignb 16
server:     resb Server_size
arena:      resb Arena_size
client:     resb Client_size
other:      resb Client_size
rect:       resd 4
handle:     resd 1
alignb 16
heap:       resb HEAP_SIZE
