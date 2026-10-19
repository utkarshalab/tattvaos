; Proprietary camera-container adapter. Uncompressed TIFF/CFA payloads use the
; sensor pipeline; compressed containers fall back to their embedded JPEG.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/image.inc"

section .text
global camera_probe
camera_probe:
    PROLOGUE_SAVE rbx,r12
    mov rbx,rdi
    mov r12,rsi
    cmp r12,16
    jb .none
    cmp word [rbx],0x4949
    je .tiff_family
    cmp word [rbx],0x4D4D
    jne .raf
.tiff_family:
    cmp word [rbx],0x4949
    jne .tiff_names
    cmp word [rbx+2],0x524F       ; IIRO: Olympus ORF
    je .orf
    cmp word [rbx+2],0x0055       ; IIU\0: Panasonic RW2
    je .rw2
    cmp word [rbx+8],0x5243       ; Canon CR2 marker
    je .cr2
.tiff_names:
    lea rdi,[rel nikon_name]
    mov rsi,5
    call .find
    test rax,rax
    jnz .nef
    lea rdi,[rel sony_name]
    mov rsi,4
    call .find
    test rax,rax
    jnz .arw
    jmp .none
.raf:
    cmp dword [rbx],0x494A5546   ; FUJI
    jne .cr3_check
    cmp dword [rbx+4],0x4D4C4946 ; FILM
    je .raf_yes
.cr3_check:
    cmp r12,12
    jb .none
    cmp dword [rbx+4],0x70797466 ; ftyp
    jne .none
    cmp dword [rbx+8],0x20787263 ; crx 
    jne .none
    mov eax,IMAGE_FMT_CR3
    jmp .out
.cr2: mov eax,IMAGE_FMT_CR2
    jmp .out
.nef: mov eax,IMAGE_FMT_NEF
    jmp .out
.arw: mov eax,IMAGE_FMT_ARW
    jmp .out
.raf_yes: mov eax,IMAGE_FMT_RAF
    jmp .out
.orf: mov eax,IMAGE_FMT_ORF
    jmp .out
.rw2: mov eax,IMAGE_FMT_RW2
    jmp .out
.none:
    xor eax,eax
.out:
    EPILOGUE_RESTORE rbx,r12
    ret

; Search first min(len,4096) bytes for rdi/rsi ASCII needle.
.find:
    mov rcx,r12
    cmp rcx,4096
    jbe .limit
    mov rcx,4096
.limit:
    cmp rcx,rsi
    jb .not_found
    xor r8,r8
.position:
    mov r9,rcx
    sub r9,rsi
    cmp r8,r9
    ja .not_found
    xor r10,r10
.compare:
    cmp r10,rsi
    jae .found
    mov al,[rbx+r8+r10]
    cmp al,[rdi+r10]
    jne .next
    inc r10
    jmp .compare
.next:
    inc r8
    jmp .position
.found:
    mov eax,1
    ret
.not_found:
    xor eax,eax
    ret

global camera_decode
camera_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    ; TIFF-derived containers may expose a directly processable CFA IFD.
    cmp r13,8
    jb .preview
    cmp word [r12],0x4949
    jne .preview
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call tiff_decode
    test rax,rax
    jnz .done
.preview:
    ; Locate a complete embedded JPEG preview. The JPEG decoder validates EOI.
    xor r14,r14
.scan:
    lea rax,[r14+3]
    cmp rax,r13
    jae .fail
    cmp byte [r12+r14],0xFF
    jne .advance
    cmp byte [r12+r14+1],0xD8
    jne .advance
    cmp byte [r12+r14+2],0xFF
    jne .advance
    mov rdi,rbx
    lea rsi,[r12+r14]
    mov rdx,r13
    sub rdx,r14
    call jpeg_decode
    test rax,rax
    jnz .done
.advance:
    inc r14
    jmp .scan
.fail:
    xor eax,eax
.done:
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

section .rodata
nikon_name: db 'NIKON'
sony_name: db 'SONY'
section .data
global camera_version
camera_version: dq 0x010000
