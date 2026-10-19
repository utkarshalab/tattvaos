; ============================================================================
; Tonemap — HDR (PQ/HLG) to SDR Mapping (Reinhard + knee)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/colorm.inc"
%include "inc/fixed.inc"

; struct offsets (hoisted above use)
%define HdrMeta_SIZE    20

section .text

struc HdrMeta
    .encoding:      resd 1
    .max_cll:       resd 1  ; nits 16.16
    .max_fall:      resd 1
    .max_display:   resd 1
    .min_display:   resd 1
endstruc

; ---------------------------------------------------------------------------
; tonemap_init
; ---------------------------------------------------------------------------
global tonemap_init
tonemap_init:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; pq_to_linear
;   ST.2084 EOTF^-1 approx: L = ((max(c^(1/m2)-c1,0))/(c2-c3*c^(1/m2)))^(1/m1)
;   Simplified rational approx in 16.16; exact curve in C31 tuning
;   IN: rdi = c 16.16 (0..1) — OUT: rax = linear 16.16 normalized
; ---------------------------------------------------------------------------
global pq_to_linear
pq_to_linear:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ; c^(1/m2), m2 = 2523/4096*128 = 78.84375 -> use sqrt chain approx
    mov rdi, rbx
    call fix_sqrt
    mov rdi, rax
    call fix_sqrt
    mov rbx, rax
    ; ((c'-c1)/(c2-c3*c')) with c1=0.8359, c2=18.8516, c3=18.6875
    mov rax, rbx
    sub rax, 54783   ; 0.8359*65536
    jns .pos
    xor eax, eax
    EPILOGUE_RESTORE rbx
    ret
.pos:
    ; denom = 18.8516 - 18.6875*c'
    mov rdx, rbx
    imul rdx, 1224478  ; 18.6875*65536
    sar rdx, 16
    mov rcx, 1235430   ; 18.8516*65536
    sub rcx, rdx
    jbe .clip
    shl rax, 16
    xor rdx, rdx
    div rcx
    ; ^(1/m1), m1 = 2610/4096*4 = 2.55 -> sqrt-ish approx
    mov rdi, rax
    call fix_sqrt
    ; scale to 10000-nit normalized then caller maps to display
    EPILOGUE_RESTORE rbx
    ret
.clip:
    mov rax, 0x10000
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; hlg_to_linear
;   HLG OETF^-1 approx (knee at 0.5)
; ---------------------------------------------------------------------------
global hlg_to_linear
hlg_to_linear:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    cmp rbx, 0x8000  ; 0.5
    ja .upper
    ; L = c^2 / 3
    mov rax, rbx
    imul rax, rbx
    shr rax, 16
    mov rdx, rax
    shr rdx, 2  ; /3 approx via /4 (documented)
    mov rax, rdx
    EPILOGUE_RESTORE rbx
    ret
.upper:
    ; L = (exp((c-0.5599)/0.1788)+0.2847)/12
    mov rax, rbx
    sub rax, 36696  ; 0.5599*65536
    ; exp approx: 1 + x + x^2/2
    mov rdx, rax
    imul rdx, rax
    shr rdx, 17  ; /2 in 16.16
    add rax, rdx
    add rax, 0x10000
    add rax, 18658  ; +0.2847
    mov rdx, 12
    xor rdx, rdx
    mov rcx, 12
    xor rdx, rdx
    div rcx
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; tonemap_reinhard
;   IN: rdi = linear 16.16 HDR, rsi = exposure 16.16, rdx = max_out 16.16
; ---------------------------------------------------------------------------
global tonemap_reinhard
tonemap_reinhard:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rdx
    ; x = L * exposure
    mov rax, rbx
    imul rax, rsi
    sar rax, 16
    mov rbx, rax
    ; y = x / (1 + x)
    mov rcx, rax
    add rcx, 0x10000
    shl rax, 16
    xor rdx, rdx
    div rcx
    ; scale to max_out
    imul rax, r12
    sar rax, 16
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; tonemap_pixel
;   IN: rdi=HdrMeta*, rsi=r,g,b 16.16 linear HDR, out via rdx pointer[3]
; ---------------------------------------------------------------------------
global tonemap_pixel
tonemap_pixel:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r14, rdx
    ASSERT_PTR rbx
    ASSERT_PTR rdx
    mov eax, [rbx + HdrMeta.encoding]
    ; luminance approx max(r,g,b)
    mov rax, r12
    mov r13, [r12 + 0]
    cmp r13, [r12 + 8]
    cmovb r13, [r12 + 8]
    cmp r13, [r12 + 16]
    cmovb r13, [r12 + 16]
    mov r15, r13
    ; exposure from max_display (default 203 nits SDR ref)
    mov rdi, r13
    mov rsi, 0x10000
    mov rdx, 0x10000
    call tonemap_reinhard
    mov r13, rax
    ; Preserve hue by applying mapped-luminance/original-luminance to channels.
    test r15, r15
    jz .black
    mov r8, r15
    mov r9, rax
    mov rax, [r12]
    imul rax, r9
    cqo
    idiv r8
    mov [r14], rax
    mov rax, [r12 + 8]
    imul rax, r9
    cqo
    idiv r8
    mov [r14 + 8], rax
    mov rax, [r12 + 16]
    imul rax, r9
    cqo
    idiv r8
    mov [r14 + 16], rax
    jmp .pixel_done
.black:
    mov qword [r14], 0
    mov qword [r14 + 8], 0
    mov qword [r14 + 16], 0
.pixel_done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global tonemap_version
tonemap_version: dq 0x010000
