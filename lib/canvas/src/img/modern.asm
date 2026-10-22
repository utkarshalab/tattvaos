; Modern image-container identification: AVIF, HEIF, and JPEG XL.
; Decoding is intentionally deferred by docs/decisions/0011; probes remain so
; callers can report recognized-but-unsupported input accurately.
%include "inc/image.inc"

section .text

; data,length -> IMAGE_FMT_* or IMAGE_FMT_UNKNOWN.
global modern_probe
modern_probe:
    test rdi,rdi
    jz .unknown
    cmp rsi,2
    jb .unknown
    cmp word [rdi],0x0AFF             ; raw JPEG XL codestream FF 0A
    je .jxl
    cmp rsi,12
    jb .unknown
    cmp dword [rdi],0x0C000000        ; JPEG XL container signature
    jne .isobmff
    cmp dword [rdi+4],0x204C584A      ; JXL<space>
    jne .isobmff
    cmp dword [rdi+8],0x0A870A0D
    je .jxl
.isobmff:
    cmp dword [rdi+4],0x70797466      ; ftyp
    jne .unknown
    mov rcx,rsi
    cmp rcx,64
    jbe .limit_ready
    mov ecx,64
.limit_ready:
    mov r8d,8
    xor r9d,r9d                       ; remember a HEIF-compatible brand
.brand:
    lea eax,[r8+4]
    cmp rax,rcx
    ja .brands_done
    mov eax,[rdi+r8]
    cmp eax,0x66697661                ; avif
    je .avif
    cmp eax,0x73697661                ; avis
    je .avif
    cmp eax,0x63696568                ; heic
    je .mark_heif
    cmp eax,0x78696568                ; heix
    je .mark_heif
    cmp eax,0x63657668                ; hevc
    je .mark_heif
    cmp eax,0x78766568                ; hevx
    je .mark_heif
    cmp eax,0x3166696D                ; mif1
    je .mark_heif
    cmp eax,0x3166736D                ; msf1
    jne .brand_next
.mark_heif:
    mov r9d,1
.brand_next:
    add r8d,4
    jmp .brand
.brands_done:
    test r9d,r9d
    jz .unknown
    mov eax,IMAGE_FMT_HEIF
    ret
.avif:
    mov eax,IMAGE_FMT_AVIF
    ret
.jxl:
    mov eax,IMAGE_FMT_JXL
    ret
.unknown:
    xor eax,eax
    ret

section .data
global modern_version
modern_version: dq 0x010000
