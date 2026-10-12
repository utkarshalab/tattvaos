; ============================================================================
; Metrics — Font-Wide Metrics (ascent, descent, line gap, bbox)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/font.inc"

section .text

struc FontMetrics {
    .units_per_em:  resd 1
    .ascent:        resd 1
    .descent:       resd 1
    .line_gap:      resd 1
    .x_min:         resd 1
    .y_min:         resd 1
    .x_max:         resd 1
    .y_max:         resd 1
}
%define FontMetrics_size    32

; ---------------------------------------------------------------------------
; metrics_get
;   IN: rdi = font*, rsi = FontMetrics* — OUT: rax = 0 ok
; ---------------------------------------------------------------------------
global metrics_get
metrics_get:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov eax, [rbx + TtfFont.units_per_em]
    mov [r12 + FontMetrics.units_per_em], eax
    mov rax, [rbx + TtfFont.hhea]
    test rax, rax
    jz .no_hhea
    jmp .hhea_ok
.no_hhea:
    mov dword [r12 + FontMetrics.ascent], 0
    mov dword [r12 + FontMetrics.descent], 0
    mov dword [r12 + FontMetrics.line_gap], 0
    jmp .head_bbox
.hhea_ok:
    mov rax, [rbx + TtfFont.hhea]
    mov rdi, rax
    add rdi, 4
    call cmap_be16
    movsx edx, ax
    mov [r12 + FontMetrics.ascent], edx
    mov rax, [rbx + TtfFont.hhea]
    mov rdi, rax
    add rdi, 6
    call cmap_be16
    movsx edx, ax
    mov [r12 + FontMetrics.descent], edx
    mov rax, [rbx + TtfFont.hhea]
    mov rdi, rax
    add rdi, 8
    call cmap_be16
    movsx edx, ax
    mov [r12 + FontMetrics.line_gap], edx
    jmp .head_bbox
.head_bbox:
    mov rax, [rbx + TtfFont.head]
    test rax, rax
    jz .done
    mov rdi, rax
    add rdi, 36
    call cmap_be16
    movsx edx, ax
    mov [r12 + FontMetrics.x_min], edx
    mov rax, [rbx + TtfFont.head]
    mov rdi, rax
    add rdi, 38
    call cmap_be16
    movsx edx, ax
    mov [r12 + FontMetrics.y_min], edx
    mov rax, [rbx + TtfFont.head]
    mov rdi, rax
    add rdi, 40
    call cmap_be16
    movsx edx, ax
    mov [r12 + FontMetrics.x_max], edx
    mov rax, [rbx + TtfFont.head]
    mov rdi, rax
    add rdi, 42
    call cmap_be16
    movsx edx, ax
    mov [r12 + FontMetrics.y_max], edx
.done:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; metrics_scale
;   IN: rdi = font*, rsi = pixel size — OUT: rax = 16.16 scale factor
; ---------------------------------------------------------------------------
global metrics_scale
metrics_scale:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov eax, [rbx + TtfFont.units_per_em]
    test eax, eax
    jz .fail
    mov ecx, eax
    mov eax, esi
    shl eax, 16
    xor edx, edx
    div ecx
    ret
.fail:
    xor rax, rax
    ret

section .data
global metrics_version
metrics_version: dq 0x010000
