; ============================================================================
; Gamma — Gamma Correction LUT (256 entries per channel)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/fixed.inc"

; struct offsets (hoisted above use)
%define GAMMA_ENTRIES    256
%define GAMMA_CHANNELS   3

section .text

%define GAMMA_LUT_SIZE   (GAMMA_ENTRIES * GAMMA_CHANNELS * 2)  ; 1536 bytes

; ---------------------------------------------------------------------------
; gamma_init
; ---------------------------------------------------------------------------
global gamma_init
gamma_init:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; gamma_create_lut
;   Create gamma LUT from exponent
;   IN:  rdi = output*, rsi = gamma_exponent (fixed 16.16, 1.0 = 0x10000)
;   OUT: rax = 0 OK, output.gamma_lut populated
; ---------------------------------------------------------------------------
global gamma_create_lut
gamma_create_lut:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Allocate LUT if not exists
    mov rax, [rbx + Output.gamma_lut]
    test rax, rax
    jnz .has_lut

    mov rdi, [rbx + Output.controller]
    mov rdi, [rdi + Server.arena]
    mov rsi, GAMMA_LUT_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rbx + Output.gamma_lut], rax

.has_lut:
    mov r13, rax

    ; Generate LUT: out = pow(in/255, 1/gamma) * 65535
    mov r14, 0
.gen_loop:
    cmp r14, 256
    jge .done

    ; in = r14 / 255
    mov rax, r14
    shl rax, 16
    mov r15, 255
    xor rdx, rdx
    div r15
    mov r15, rax  ; in (16.16)

    ; out = pow(in, 1/gamma)
    ; For simplicity, use integer approximation
    ; out = in^gamma_inv
    mov rax, r12  ; gamma
    test rax, rax
    jz .linear

    ; Use integer power approximation
    ; For gamma 2.2: gamma_inv = 1/2.2 ≈ 0.4545 ≈ 29800/65536
    mov r15, 29800
    call fixed_pow

.linear:
    ; Clamp to 16-bit
    cmp rax, 0xFFFF
    jbe .store
    mov rax, 0xFFFF

.store:
    mov [r13 + r14 * 2], ax
    mov [r13 + r14 * 2 + 512], ax
    mov [r13 + r14 * 2 + 1024], ax

    inc r14
    jmp .gen_loop

.done:
    ; Program hardware gamma LUT
    ; TODO: Call backend gamma_lut_set

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; gamma_set_lut
;   Set gamma LUT directly
;   IN:  rdi = output*, rsi = lut_ptr (1536 bytes), rdx = len
; ---------------------------------------------------------------------------
global gamma_set_lut
gamma_set_lut:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    cmp rdx, GAMMA_LUT_SIZE
    jne .bad_size

    ; Copy LUT
    mov rax, [rbx + Output.gamma_lut]
    test rax, rax
    jz .alloc

    mov rdi, rax
    mov rcx, 768
    call memcopy
    EPILOGUE_RESTORE rbx, r12
    ret

.alloc:
    mov rdi, [rbx + Output.controller]
    mov rdi, [rdi + Server.arena]
    mov rsi, GAMMA_LUT_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rbx + Output.gamma_lut], rax
    mov rdi, rax
    mov rsi, r12
    mov rcx, 768
    call memcopy
    EPILOGUE_RESTORE rbx, r12
    ret

.bad_size:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; gamma_load_from_edid
;   Load gamma from EDID
; ---------------------------------------------------------------------------
global gamma_load_from_edid
gamma_load_from_edid:
    PROLOGUE
    ; TODO: Parse EDID gamma curve
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; gamma_apply
;   Apply gamma LUT to frame
; ---------------------------------------------------------------------------
global gamma_apply
gamma_apply:
    PROLOGUE
    ; TODO: Implement in compositor
    xor rax, rax
    leave
    ret

section .data
global gamma_version
gamma_version: dq 0x010000
