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
extern region_init
extern region_add_rect
extern region_subtract_rect
extern region_intersect_rect
extern region_contains_point
extern region_clear

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
    CASE tr_properties
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

; QA-08: regions against a model. From four seeds, 60 random steps each on
; a 16x16 grid: add, subtract or intersect a rectangle (anywhere from -2,
; up to 8 each way, empty too), the region and the grid of what it should
; hold cleared every 20; after every step each of the 256 points is in the
; region exactly when the grid says so
%define GRID        16
%define PROP_STEPS  60
%define PROP_STORE  (1024 * 1024)
tr_properties:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    xor r14d, r14d                      ; the seed
.seed:
    lea rax, [rel prop_seeds]
    mov rax, [rax + r14 * 8]
    mov [rel prop_seed], rax
    lea rdi, [rel prop_arena]
    lea rsi, [rel prop_store]
    mov edx, PROP_STORE
    call arena_init
    lea rdi, [rel prop_arena]
    call region_init
    test rax, rax
    jz .fail
    mov rbx, rax
    xor r12d, r12d                      ; the step
.step:
    mov eax, r12d
    xor edx, edx
    mov ecx, 20
    div ecx
    test edx, edx
    jnz .rect
    mov rdi, rbx                        ; every 20: both cleared
    call region_clear
    lea rdi, [rel prop_grid]
    xor eax, eax
    mov ecx, GRID * GRID
    rep stosb
.rect:
    mov edi, GRID
    call prop_below
    sub eax, 2
    mov [rel prop_rect], eax
    mov edi, GRID
    call prop_below
    sub eax, 2
    mov [rel prop_rect + 4], eax
    mov edi, 9
    call prop_below
    mov [rel prop_rect + 8], eax
    mov edi, 9
    call prop_below
    mov [rel prop_rect + 12], eax
    mov edi, 3
    call prop_below
    mov r13d, eax                       ; 0 add, 1 subtract, 2 intersect
    mov rdi, rbx
    lea rsi, [rel prop_rect]
    cmp r13d, 1
    je .subtract
    ja .intersect
    call region_add_rect
    jmp .model
.subtract:
    call region_subtract_rect
    jmp .model
.intersect:
    call region_intersect_rect
.model:
    test rax, rax
    js .fail
    xor ecx, ecx                        ; the grid, the same way
.cell:
    mov eax, ecx
    and eax, GRID - 1                   ; x
    mov edx, ecx
    shr edx, 4                          ; y
    xor r8d, r8d                        ; inside the rectangle?
    cmp eax, [rel prop_rect]
    jl .placed
    cmp edx, [rel prop_rect + 4]
    jl .placed
    mov r9d, [rel prop_rect]
    add r9d, [rel prop_rect + 8]
    cmp eax, r9d
    jge .placed
    mov r9d, [rel prop_rect + 4]
    add r9d, [rel prop_rect + 12]
    cmp edx, r9d
    jge .placed
    mov r8d, 1
.placed:
    lea r9, [rel prop_grid]
    cmp r13d, 1
    je .cleared
    ja .kept
    test r8d, r8d                       ; add: in it, set
    jz .next_cell
    mov byte [r9 + rcx], 1
    jmp .next_cell
.cleared:
    test r8d, r8d                       ; subtract: in it, clear
    jz .next_cell
    mov byte [r9 + rcx], 0
    jmp .next_cell
.kept:
    test r8d, r8d                       ; intersect: outside it, clear
    jnz .next_cell
    mov byte [r9 + rcx], 0
.next_cell:
    inc ecx
    cmp ecx, GRID * GRID
    jb .cell
    xor r13d, r13d                      ; every point agrees
.check:
    mov rdi, rbx
    mov esi, r13d
    and esi, GRID - 1
    mov edx, r13d
    shr edx, 4
    call region_contains_point
    lea rcx, [rel prop_grid]
    movzx ecx, byte [rcx + r13]
    cmp eax, ecx
    jne .fail
    inc r13d
    cmp r13d, GRID * GRID
    jb .check
    inc r12d
    cmp r12d, PROP_STEPS
    jb .step
    inc r14d
    cmp r14d, 4
    jb .seed
    xor eax, eax
    jmp .out
.fail:
    mov eax, 1
.out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -> rax = the next random number (xorshift64), from prop_seed
prop_random:
    mov rax, [rel prop_seed]
    mov rdx, rax
    shl rdx, 13
    xor rax, rdx
    mov rdx, rax
    shr rdx, 7
    xor rax, rdx
    mov rdx, rax
    shl rdx, 17
    xor rax, rdx
    mov [rel prop_seed], rax
    ret

; edi = n -> eax = a random number below n
prop_below:
    push rdi
    call prop_random
    pop rcx
    xor edx, edx
    div rcx
    mov eax, edx
    ret

section .rodata
alignb 8
prop_seeds:     dq 0x9E3779B97F4A7C15, 0x0123456789ABCDEF, 0xD1B54A32D192ED03, 0x8CB92BA72F3D8DD7

section .bss
alignb 16
prop_store:     resb PROP_STORE
prop_arena:     resb Arena_size
prop_seed:      resq 1
prop_rect:      resd 4
prop_grid:      resb GRID * GRID
alignb 16
server:     resb Server_size
arena:      resb Arena_size
client:     resb Client_size
other:      resb Client_size
rect:       resd 4
handle:     resd 1
alignb 16
heap:       resb HEAP_SIZE
