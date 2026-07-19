; =============================================================================
; Tattva OS — boot/stage2/cpu/features.asm
; =============================================================================
; CPU feature flag utilities.
;
; Provides diagnostic printing of detected CPU features and a helper
; to query individual feature bits. Works with the feature bitmap stored
; at FEATURES_DEST by cpuid.asm.
;
; Feature bitmap layout (matches main.asm constants):
;   Bit 0: CPU_FEAT_LM      — Long mode (64-bit)
;   Bit 1: CPU_FEAT_NX      — NX/XD no-execute bit
;   Bit 2: CPU_FEAT_SSE     — SSE
;   Bit 3: CPU_FEAT_SSE2    — SSE2
;   Bit 4: CPU_FEAT_AVX     — AVX (256-bit)
;   Bit 5: CPU_FEAT_AVX2    — AVX2
;   Bit 6: CPU_FEAT_AVX512  — AVX-512F
;   Bit 7: CPU_FEAT_AMX     — AMX (matrix extensions)
;
; Author:  Utkarsha Labs
; Target:  x86, real mode (16-bit)
; =============================================================================

%ifndef FEATURES_ASM
%define FEATURES_ASM

[BITS 16]

; =============================================================================
; cpu_features_print — print all detected CPU features to UART
; Input:  none (reads from FEATURES_DEST)
; Output: none
; Clobbers: AX, BX, CX, SI
;
; Output format (UART):
;   "CPU Features: LM NX SSE SSE2 AVX"
;   Only prints names of features that are present.
; =============================================================================
cpu_features_print:
    push eax
    push ecx
    push si

    mov si, msg_feat_prefix
    call uart_print                 ; "CPU Features: "

    mov eax, [FEATURES_DEST]        ; load feature bitmap
    mov ecx, 0                      ; bit index

.check_loop:
    cmp ecx, FEAT_TABLE_COUNT
    jae .newline                    ; done with all features

    bt eax, ecx                    ; test bit ECX in EAX
    jnc .skip                      ; bit not set → skip

    ; Bit is set — print the feature name
    push eax
    push ecx

    ; Look up feature name: feat_names_table[ECX * 2] is a word pointer
    shl ecx, 1                     ; ECX * 2 (word index)
    mov si, [feat_names_table + ecx]
    call uart_print                 ; print feature name

    ; Print space separator
    mov al, ' '
    call uart_putc

    pop ecx
    pop eax

.skip:
    inc ecx
    jmp .check_loop

.newline:
    ; Print CRLF
    mov al, 0x0D
    call uart_putc
    mov al, 0x0A
    call uart_putc

    pop si
    pop ecx
    pop eax
    ret

; =============================================================================
; cpu_features_has — check if a specific feature is present
; Input:  EAX = feature bit mask (e.g. CPU_FEAT_LM, CPU_FEAT_AVX)
; Output: CF clear = feature present, CF set = feature absent
; Clobbers: none (preserves all registers)
;
; Usage:
;   mov eax, CPU_FEAT_AVX
;   call cpu_features_has
;   jc .no_avx                    ; CF set = not present
; =============================================================================
cpu_features_has:
    push ebx

    mov ebx, [FEATURES_DEST]        ; load feature bitmap
    test ebx, eax                    ; test requested bits
    jz .absent

    pop ebx
    clc                              ; CF clear = present
    ret

.absent:
    pop ebx
    stc                              ; CF set = absent
    ret

; =============================================================================
; cpu_features_count — count number of detected features
; Input:  none (reads from FEATURES_DEST)
; Output: EAX = number of features set (0-8)
; Clobbers: none (preserves other registers)
; =============================================================================
cpu_features_count:
    push ecx
    push edx

    mov eax, [FEATURES_DEST]
    xor ecx, ecx                    ; counter = 0

.count_loop:
    test eax, eax                   ; any bits left?
    jz .count_done
    mov edx, eax
    dec edx                         ; EAX - 1
    and eax, edx                    ; clear lowest set bit (Brian Kernighan)
    inc ecx
    jmp .count_loop

.count_done:
    mov eax, ecx                    ; return count in EAX

    pop edx
    pop ecx
    ret

; =============================================================================
; Data — feature name strings and lookup table
; =============================================================================

msg_feat_prefix:    db "CPU Features: ", 0

feat_str_lm:        db "LM", 0
feat_str_nx:        db "NX", 0
feat_str_sse:       db "SSE", 0
feat_str_sse2:      db "SSE2", 0
feat_str_avx:       db "AVX", 0
feat_str_avx2:      db "AVX2", 0
feat_str_avx512:    db "AVX512", 0
feat_str_amx:       db "AMX", 0

; Pointer table indexed by bit position (0-7)
feat_names_table:
    dw feat_str_lm                  ; bit 0: LM
    dw feat_str_nx                  ; bit 1: NX
    dw feat_str_sse                 ; bit 2: SSE
    dw feat_str_sse2                ; bit 3: SSE2
    dw feat_str_avx                 ; bit 4: AVX
    dw feat_str_avx2                ; bit 5: AVX2
    dw feat_str_avx512              ; bit 6: AVX512
    dw feat_str_amx                 ; bit 7: AMX

FEAT_TABLE_COUNT equ 8

%endif ; FEATURES_ASM
