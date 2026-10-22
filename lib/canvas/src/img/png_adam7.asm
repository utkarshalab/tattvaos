; PNG Adam7 pass expansion. Each pass is unfiltered independently, then
; scattered into a filter-zero full-size packed raster.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/image.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern png_unfilter_row
extern png_unfilter

section .text
global png_adam7_expand
png_adam7_expand:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,128
    mov rbx,rdi                    ; arena
    mov r12,rsi                   ; PngImage
    mov r13,rdx                   ; compressed output base
    lea rax,[rdx+rcx]
    jc .fail
    mov [rsp],rax                 ; source end
    mov r14,r13                   ; source cursor

    ; Full packed row stride, including a zero filter byte.
    mov eax,[r12 + PngImage.width]
    movzx ecx,byte [r12 + PngImage.channels]
    imul rax,rcx
    movzx ecx,byte [r12 + PngImage.bit_depth]
    imul rax,rcx
    add rax,7
    shr rax,3
    inc rax
    mov [rsp+8],rax
    mov ecx,[r12 + PngImage.height]
    imul rax,rcx
    jo .fail
    mov [rsp+120],rax              ; full allocation size
    mov rdi,rbx
    mov rsi,rax
    call arena_alloc
    test rax,rax
    jz .fail
    mov r15,rax                    ; full filtered raster
    mov rcx,[rsp+120]
    mov rdi,r15
    xor eax,eax
.clear:
    test rcx,rcx
    jz .cleared
    mov [rdi],al
    inc rdi
    dec rcx
    jmp .clear
.cleared:
    ; Filter bytes-per-pixel = max(1, ceil(channels*depth/8)).
    movzx eax,byte [r12 + PngImage.channels]
    movzx ecx,byte [r12 + PngImage.bit_depth]
    imul eax,ecx
    add eax,7
    shr eax,3
    test eax,eax
    jnz .bpp_ok
    inc eax
.bpp_ok:
    mov [rsp+16],rax
    mov qword [rsp+24],0           ; pass

.pass_loop:
    mov rax,[rsp+24]
    cmp rax,7
    jae .passes_done
    lea rdx,[rel adam7_x0]
    movzx ecx,byte [rdx+rax]
    mov [rsp+72],rcx
    lea rdx,[rel adam7_y0]
    movzx ecx,byte [rdx+rax]
    mov [rsp+80],rcx
    lea rdx,[rel adam7_dx]
    movzx ecx,byte [rdx+rax]
    mov [rsp+88],rcx
    lea rdx,[rel adam7_dy]
    movzx ecx,byte [rdx+rax]
    mov [rsp+96],rcx

    mov eax,[r12 + PngImage.width]
    cmp rax,[rsp+72]
    jbe .next_pass
    sub rax,[rsp+72]
    add rax,[rsp+88]
    dec rax
    xor edx,edx
    div qword [rsp+88]
    mov [rsp+32],rax               ; pass width
    mov eax,[r12 + PngImage.height]
    cmp rax,[rsp+80]
    jbe .next_pass
    sub rax,[rsp+80]
    add rax,[rsp+96]
    dec rax
    xor edx,edx
    div qword [rsp+96]
    mov [rsp+40],rax               ; pass height

    mov rax,[rsp+32]
    movzx ecx,byte [r12 + PngImage.channels]
    imul rax,rcx
    movzx ecx,byte [r12 + PngImage.bit_depth]
    imul rax,rcx
    add rax,7
    shr rax,3
    mov [rsp+48],rax               ; pass row bytes
    mov qword [rsp+56],0           ; previous pass row
    mov qword [rsp+64],0           ; pass row index

.row_loop:
    mov rax,[rsp+64]
    cmp rax,[rsp+40]
    jae .next_pass
    mov rax,r14
    add rax,[rsp+48]
    inc rax
    jc .fail
    cmp rax,[rsp]
    ja .fail
    cmp byte [r14],4
    ja .fail
    inc r14                       ; current row data
    mov rdi,r14
    mov rsi,[rsp+56]
    mov rdx,[rsp+48]
    mov rcx,[rsp+16]
    call png_unfilter_row
    test rax,rax
    jnz .fail

    ; Destination row = y0 + pass_row*dy.
    mov rax,[rsp+64]
    imul rax,[rsp+96]
    add rax,[rsp+80]
    imul rax,[rsp+8]
    lea rax,[r15+rax+1]
    mov [rsp+112],rax
    xor r13d,r13d                 ; pass x
    cmp byte [r12 + PngImage.bit_depth],8
    jb .scatter_packed
    movzx eax,byte [r12 + PngImage.channels]
    movzx ecx,byte [r12 + PngImage.bit_depth]
    shr ecx,3
    imul eax,ecx
    mov [rsp+104],rax             ; bytes per pixel
.scatter_bytes:
    cmp r13,[rsp+32]
    jae .row_done
    mov rax,r13
    imul rax,[rsp+104]
    lea rsi,[r14+rax]
    mov rax,r13
    imul rax,[rsp+88]
    add rax,[rsp+72]
    imul rax,[rsp+104]
    mov rdi,[rsp+112]
    add rdi,rax
    mov rcx,[rsp+104]
.copy_pixel:
    test rcx,rcx
    jz .next_byte_pixel
    mov al,[rsi]
    mov [rdi],al
    inc rsi
    inc rdi
    dec rcx
    jmp .copy_pixel
.next_byte_pixel:
    inc r13
    jmp .scatter_bytes

.scatter_packed:
    ; Packed formats have one sample per pixel (gray or indexed).
    cmp r13,[rsp+32]
    jae .row_done
    movzx r10d,byte [r12 + PngImage.bit_depth]
    mov eax,r13d
    imul eax,r10d
    mov ecx,eax
    and ecx,7
    shr eax,3
    movzx r9d,byte [r14+rax]
    mov edx,8
    sub edx,r10d
    sub edx,ecx
    mov ecx,edx
    shr r9d,cl
    mov eax,1
    mov ecx,r10d
    shl eax,cl
    dec eax
    and r9d,eax                   ; decoded sample

    mov rax,r13
    imul rax,[rsp+88]
    add rax,[rsp+72]              ; destination x
    mov rcx,rax
    imul eax,r10d
    mov edx,eax
    and edx,7
    shr eax,3
    mov rdi,[rsp+112]
    add rdi,rax
    mov eax,8
    sub eax,r10d
    sub eax,edx
    mov ecx,eax
    shl r9d,cl
    or [rdi],r9b
    inc r13
    jmp .scatter_packed

.row_done:
    mov [rsp+56],r14
    add r14,[rsp+48]
    inc qword [rsp+64]
    jmp .row_loop

.next_pass:
    inc qword [rsp+24]
    jmp .pass_loop

.passes_done:
    cmp r14,[rsp]
    jne .fail
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r15
    call png_unfilter
    add rsp,128
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.fail:
    xor eax,eax
    add rsp,128
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

section .rodata
adam7_x0: db 0,4,0,2,0,1,0
adam7_y0: db 0,0,4,0,2,0,1
adam7_dx: db 8,8,4,4,2,2,1
adam7_dy: db 8,8,8,4,4,2,2

section .data
global png_adam7_version
png_adam7_version: dq 0x010000
