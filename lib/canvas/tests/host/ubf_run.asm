; ============================================================================
; ubf_run — load a Canvas UBF and run it to its first frame
; ============================================================================
; A loader written from docs/UBF_SPEC.md §9, standing where the kernel's does:
; it maps the image at 1 TiB, far from anything linked here, offers exactly the
; exports docs/KERNEL_NEEDS.md lists for the first frame, gives each segment
; its own protection and leaves gaps inaccessible, and starts the entry point
; on a fiber-sized stack with a guard page below it.
;
; ut_fb_info reports a small poisoned framebuffer with a pitch wider than its
; rows. After a few turns of the program's loop, ut_yield checks the login
; screen is up: every visible pixel outside the password field and its label
; holds the greeter's background, every one inside the field the field's
; colours, the caret is drawn, the label has ink, and the bytes past each row
; are still poison.
;
; usage: ubf_run <file.ubf>   exit 0 when the frame is right
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/channel.inc"
%include "inc/greeter.inc"

default rel

extern ut_mem_alloc
extern ut_mem_free
extern ut_time_now_ns
extern ut_log_write
extern ut_log_printf
extern ut_task_exit

%define SYS_READ            0
%define SYS_OPEN            2
%define SYS_FSTAT           5
%define SYS_MMAP            9
%define SYS_MPROTECT        10

%define PROT_NONE           0
%define PROT_READ           1
%define PROT_RW             3
%define MAP_PRIVATE         0x02
%define MAP_FIXED           0x10
%define MAP_ANONYMOUS       0x20
%define STAT_SIZE           48
%define STAT_BYTES          144

%define LOAD_BASE           (1 << 40)
%define PAGE                4096

; The spec's fields
%define H_MAGIC             0x00
%define H_MEM_SIZE          0x10
%define H_ENTRY             0x18
%define H_STACK             0x20
%define H_SEG_COUNT         0x24
%define H_SEG_OFF           0x28
%define H_REL_OFF           0x2C
%define H_REL_COUNT         0x30
%define H_IMP_OFF           0x34
%define H_IMP_COUNT         0x38
%define H_STR_OFF           0x44
%define SEG_TYPE            0x00
%define SEG_PROT            0x04
%define SEG_FILE_OFF        0x08
%define SEG_FILE_SIZE       0x0C
%define SEG_MEM_OFF         0x10
%define SEG_MEM_SIZE        0x18
%define SEG_BYTES           32
%define IMP_NAME            0x00
%define IMP_SLOT            0x08
%define IMP_FLAGS           0x0C
%define IMP_BYTES           16
%define IMP_WEAK            1

%define DEFAULT_STACK       16384       ; FIBER_STACK_SIZE in the kernel

; The fake framebuffer
%define FB_WIDTH            400         ; room for the greeter's field
%define FB_HEIGHT           120         ; and the label above the field
%define FB_PITCH            (416 * 4)
%define FB_POISON           0xDEADBEEF
%define TURNS_BEFORE_CHECK  6           ; the greeter is up after the first

; Where the greeter puts its field and caret on this framebuffer
%define FIELD_X             ((FB_WIDTH - GREETER_FIELD_W) / 2)
%define FIELD_Y             ((FB_HEIGHT - GREETER_FIELD_H) / 2)
%define CARET_X             (FIELD_X + GREETER_PAD)
%define CARET_Y             (FIELD_Y + (GREETER_FIELD_H - GREETER_CARET_H) / 2)
%define LABEL_Y             (FIELD_Y - GREETER_LABEL_GAP - GREETER_LABEL_H)

section .text

global _start
_start:
    mov rdi, [rsp + 16]                 ; argv[1]
    test rdi, rdi
    jz fail_usage

    ; The file, whole
    mov eax, SYS_OPEN
    xor esi, esi
    xor edx, edx
    syscall
    test rax, rax
    js fail_file
    mov r15, rax                        ; descriptor
    sub rsp, STAT_BYTES
    mov eax, SYS_FSTAT
    mov rdi, r15
    mov rsi, rsp
    syscall
    test rax, rax
    js fail_file
    mov rsi, [rsp + STAT_SIZE]
    add rsp, STAT_BYTES
    mov eax, SYS_MMAP
    xor edi, edi
    mov edx, PROT_READ
    mov r10d, MAP_PRIVATE
    mov r8, r15
    xor r9d, r9d
    syscall
    test rax, rax
    js fail_file
    mov rbx, rax                        ; rbx = the file
    cmp dword [rbx + H_MAGIC], 0x00464255
    jne fail_file

    ; 1. Reserve the image, writable and not executable
    mov eax, SYS_MMAP
    mov rdi, LOAD_BASE
    mov rsi, [rbx + H_MEM_SIZE]
    mov edx, PROT_RW
    mov r10d, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED
    mov r8, -1
    xor r9d, r9d
    syscall
    test rax, rax
    js fail_map
    mov r12, rax                        ; r12 = the load address

    ; 2. Segment bytes; the rest is already zero
    xor r13d, r13d
.copy:
    cmp r13d, [rbx + H_SEG_COUNT]
    jae .copied
    call segment_entry
    mov ecx, [rax + SEG_FILE_SIZE]
    mov esi, [rax + SEG_FILE_OFF]
    add rsi, rbx
    mov rdi, [rax + SEG_MEM_OFF]
    add rdi, r12
    rep movsb
    inc r13d
    jmp .copy
.copied:

    ; 3. Relocations
    mov ecx, [rbx + H_REL_COUNT]
    mov esi, [rbx + H_REL_OFF]
    add rsi, rbx
.reloc:
    test ecx, ecx
    jz .relocated
    mov eax, [rsi]
    add [r12 + rax], r12
    add rsi, 8
    dec ecx
    jmp .reloc
.relocated:

    ; 4. Imports, against exactly the export table below
    xor r13d, r13d
.import:
    cmp r13d, [rbx + H_IMP_COUNT]
    jae .imported
    mov eax, r13d
    imul eax, IMP_BYTES
    add eax, [rbx + H_IMP_OFF]
    lea r14, [rbx + rax]                ; r14 = the entry
    mov edi, [r14 + IMP_NAME]
    add edi, [rbx + H_STR_OFF]
    add rdi, rbx
    call find_export
    test rax, rax
    jnz .resolved
    test dword [r14 + IMP_FLAGS], IMP_WEAK
    jz fail_import                      ; rdi still names it
.resolved:
    mov ecx, [r14 + IMP_SLOT]
    mov [r12 + rcx], rax
    inc r13d
    jmp .import
.imported:

    ; 5. Nothing is reachable but each segment, with its own protection
    mov eax, SYS_MPROTECT
    mov rdi, r12
    mov rsi, [rbx + H_MEM_SIZE]
    mov edx, PROT_NONE
    syscall
    xor r13d, r13d
.protect:
    cmp r13d, [rbx + H_SEG_COUNT]
    jae .protected
    call segment_entry
    mov rdi, [rax + SEG_MEM_OFF]
    add rdi, r12
    mov rsi, [rax + SEG_MEM_SIZE]
    add rsi, PAGE - 1
    and rsi, -PAGE
    mov edx, [rax + SEG_PROT]
    mov eax, SYS_MPROTECT
    syscall
    test rax, rax
    js fail_map
    inc r13d
    jmp .protect
.protected:

    ; The fiber's stack, with a guard page under it
    mov esi, [rbx + H_STACK]
    test esi, esi
    jnz .stack_sized
    mov esi, DEFAULT_STACK
.stack_sized:
    add rsi, PAGE - 1
    and rsi, -PAGE
    mov r13, rsi                        ; r13 = stack bytes
    add rsi, PAGE
    mov eax, SYS_MMAP
    xor edi, edi
    mov edx, PROT_RW
    mov r10d, MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    xor r9d, r9d
    syscall
    test rax, rax
    js fail_map
    mov r14, rax
    mov eax, SYS_MPROTECT
    mov rdi, r14
    mov esi, PAGE
    mov edx, PROT_NONE
    syscall
    add r14, PAGE                       ; r14 = lowest usable stack byte
    mov [stack_low], r14
    mov [stack_bytes], r13

    ; The poisoned framebuffer
    lea rdi, [framebuffer]
    mov eax, FB_POISON
    mov ecx, (FB_PITCH * FB_HEIGHT) / 4
    rep stosd

    ; 6. Start it: 16-byte aligned, minus 8 after the call
    mov rax, [rbx + H_ENTRY]
    add rax, r12
    lea rsp, [r14 + r13]
    xor edi, edi                        ; no start block yet
    xor ebp, ebp
    call rax

    ; The server never returns
    lea rdi, [msg_returned]
    jmp fail_message

; rax = segment r13's entry
segment_entry:
    mov eax, r13d
    imul eax, SEG_BYTES
    add eax, [rbx + H_SEG_OFF]
    add rax, rbx
    ret

; rdi = name (kept), rax = its address or 0
find_export:
    lea r8, [exports]
.next:
    mov rsi, [r8]
    test rsi, rsi
    jz .none
    xor ecx, ecx
.compare:
    mov al, [rdi + rcx]
    cmp al, [rsi + rcx]
    jne .different
    inc rcx
    test al, al
    jnz .compare
    mov rax, [r8 + 8]
    ret
.different:
    add r8, 16
    jmp .next
.none:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; The two exports the kernel will provide and the host shim does not
; ---------------------------------------------------------------------------

; rdi = 32-byte block
run_fb_info:
    lea rax, [framebuffer]
    mov [rdi], rax
    mov dword [rdi + 8], FB_WIDTH
    mov dword [rdi + 12], FB_HEIGHT
    mov dword [rdi + 16], FB_PITCH
    mov dword [rdi + 20], 0
    mov qword [rdi + 24], FB_PITCH * FB_HEIGHT
    xor eax, eax
    ret

run_yield:
    inc qword [turns]
    cmp qword [turns], TURNS_BEFORE_CHECK
    jae .check
    xor eax, eax
    ret
.check:
    lea rsi, [framebuffer]
    xor edx, edx                        ; y
.row:
    xor ecx, ecx                        ; x
.pixel:
    mov eax, [rsi + rcx * 4]
    cmp ecx, FB_WIDTH
    jae .past_row
    cmp ecx, FIELD_X
    jb .outside
    cmp ecx, FIELD_X + GREETER_FIELD_W
    jae .outside
    cmp edx, LABEL_Y
    jb .outside
    cmp edx, FIELD_Y
    jb .pixel_ok                        ; the label: text, any colour
    cmp ecx, FIELD_X + GREETER_FIELD_W
    jae .outside
    cmp edx, FIELD_Y
    jb .outside
    cmp edx, FIELD_Y + GREETER_FIELD_H
    jae .outside
    cmp eax, GREETER_BORDER
    je .pixel_ok
    cmp eax, GREETER_FIELD
    je .pixel_ok
    cmp eax, GREETER_INK
    je .pixel_ok
    jmp .wrong_pixel
.outside:
    cmp eax, GREETER_BG
    jne .wrong_pixel
    jmp .pixel_ok
.past_row:
    cmp eax, FB_POISON
    jne .wrong_edge
.pixel_ok:
    inc ecx
    cmp ecx, FB_PITCH / 4
    jb .pixel
    add rsi, FB_PITCH
    inc edx
    cmp edx, FB_HEIGHT
    jb .row
    lea rax, [framebuffer]
    cmp dword [rax + CARET_Y * FB_PITCH + CARET_X * 4], GREETER_INK
    jne .wrong_pixel                    ; drawn, not just cleared

    ; The label has ink: not all of its box is the background
    lea rsi, [framebuffer + LABEL_Y * FB_PITCH + FIELD_X * 4]
    mov edx, GREETER_LABEL_H
.label_row:
    xor ecx, ecx
.label_pixel:
    cmp dword [rsi + rcx * 4], GREETER_BG
    jne .labelled
    inc ecx
    cmp ecx, GREETER_FIELD_W
    jb .label_pixel
    add rsi, FB_PITCH
    dec edx
    jnz .label_row
    lea rdi, [msg_label]
    jmp fail_message
.labelled:

    ; How much of the stack the server has touched
    mov rcx, [stack_low]
    mov rdx, [stack_bytes]
    lea rsi, [rcx + rdx]
.scan:
    cmp qword [rcx], 0
    jne .scanned
    add rcx, 8
    cmp rcx, rsi
    jb .scan
.scanned:
    sub rsi, rcx
    mov rdx, [stack_bytes]
    lea rdi, [msg_ok]
    call ut_log_printf
    xor edi, edi
    call ut_task_exit
.wrong_pixel:
    lea rdi, [msg_pixel]
    jmp fail_message
.wrong_edge:
    lea rdi, [msg_edge]
    jmp fail_message

; ---------------------------------------------------------------------------
; Failures: a line and a nonzero exit
; ---------------------------------------------------------------------------
fail_usage:
    lea rdi, [msg_usage]
    jmp fail_message
fail_file:
    lea rdi, [msg_file]
    jmp fail_message
fail_map:
    lea rdi, [msg_map]
    jmp fail_message
fail_import:
    mov rsi, rdi
    lea rdi, [msg_import]
fail_message:
    and rsp, -16
    call ut_log_printf
    mov edi, 1
    call ut_task_exit

section .rodata

; Exactly docs/KERNEL_NEEDS.md, Step 1
exports:
    dq name_mem_alloc, ut_mem_alloc
    dq name_mem_free, ut_mem_free
    dq name_time, ut_time_now_ns
    dq name_log, ut_log_write
    dq name_fb, run_fb_info
    dq name_yield, run_yield
    dq 0, 0

name_mem_alloc: db "ut_mem_alloc", 0
name_mem_free:  db "ut_mem_free", 0
name_time:      db "ut_time_now_ns", 0
name_log:       db "ut_log_write", 0
name_fb:        db "ut_fb_info", 0
name_yield:     db "ut_yield", 0

msg_usage:      db "usage: ubf_run <file.ubf>", 10, 0
msg_file:       db "ubf_run: cannot read the file", 10, 0
msg_map:        db "ubf_run: cannot map the image", 10, 0
msg_import:     db "ubf_run: nothing exports %s", 10, 0
msg_returned:   db "ubf_run: the server returned", 10, 0
msg_label:      db "ubf_run: the label above the field has no ink", 10, 0
msg_pixel:      db "ubf_run: a visible pixel is not the login screen's", 10, 0
msg_edge:       db "ubf_run: a write went past the end of a row", 10, 0
msg_ok:         db "ubf_run: first frame right, %d of %d stack bytes used", 10, 0

section .bss

alignb 8
turns:          resq 1
stack_low:      resq 1
stack_bytes:    resq 1
alignb 16
framebuffer:    resb FB_PITCH * FB_HEIGHT
