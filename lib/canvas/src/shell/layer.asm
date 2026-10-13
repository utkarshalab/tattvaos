; ============================================================================
; Layer — Layer Shell (Panels, Lock Screen, Wallpaper, OSD)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

; struct offsets (hoisted above use)
%define Layer_size    80
%define LAYER_BACKGROUND      0
%define LAYER_BOTTOM          1
%define LAYER_NORMAL          2
%define LAYER_TOP             3
%define LAYER_OVERLAY         4
%define LAYER_LOCK            5
%define LAYER_ANCHOR_TOP      (1 << 0)
%define LAYER_ANCHOR_BOTTOM   (1 << 1)
%define LAYER_ANCHOR_LEFT     (1 << 2)
%define LAYER_ANCHOR_RIGHT    (1 << 3)
%define KEYBOARD_INTERACTIVITY_NONE      0
%define KEYBOARD_INTERACTIVITY_EXCLUSIVE 1
%define KEYBOARD_INTERACTIVITY_ON_DEMAND 2
%define Layer_surface          0
%define Layer_shell            8
%define Layer_output           16
%define Layer_layer            24
%define Layer_namespace        32
%define Layer_anchor           40
%define Layer_exclusive_zone   44
%define Layer_margin_top       48
%define Layer_margin_bottom    52
%define Layer_margin_left      56
%define Layer_margin_right     60
%define Layer_keyboard_interactivity 64
%define Layer_next             72
%define Layer.next 72
%define Layer_size             80

section .text

struc Layer
    .surface:           resq 1
    .shell:             resq 1
    .output:            resq 1
    .layer:             resd 1
    .namespace:         resq 1
    .anchor:            resd 1
    .exclusive_zone:    resd 1
    .margin_top:        resd 1
    .margin_bottom:     resd 1
    .margin_left:       resd 1
    .margin_right:      resd 1
    .keyboard_interactivity: resb 1
endstruc




; ---------------------------------------------------------------------------
; layer_create
;   Create layer surface
; ---------------------------------------------------------------------------
global layer_create
layer_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate layer
    mov rdi, [rbx + Server.arena]
    mov rsi, Layer_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Initialize
    mov qword [rbx + Layer.surface], r12
    mov qword [rbx + Layer.shell], r13
    mov qword [rbx + Layer.output], 0
    mov dword [rbx + Layer.layer], LAYER_NORMAL
    mov qword [rbx + Layer.namespace], 0
    mov dword [rbx + Layer.anchor], 0
    mov dword [rbx + Layer.exclusive_zone], 0
    mov dword [rbx + Layer.margin_top], 0
    mov dword [rbx + Layer.margin_bottom], 0
    mov dword [rbx + Layer.margin_left], 0
    mov dword [rbx + Layer.margin_right], 0
    mov byte [rbx + Layer.keyboard_interactivity], KEYBOARD_INTERACTIVITY_NONE

    ; Set surface role
    mov dword [r12 + Surface.role], SHELL_ROLE_LAYER
    mov qword [r12 + Surface.role_data], rbx

    ; Add to shell's layer list
    mov r14, [r13 + Shell.layers]
    mov [rbx + Layer.next], r14
    mov [r13 + Shell.layers], rbx

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; layer_destroy
; ---------------------------------------------------------------------------
global layer_destroy
layer_destroy:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Remove from shell list
    ; TODO

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; layer_set_output
; ---------------------------------------------------------------------------
global layer_set_output
layer_set_output:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov [rbx + Layer.output], r12
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; layer_set_layer
;   Set layer level (background, bottom, normal, top, overlay, lock)
; ---------------------------------------------------------------------------
global layer_set_layer
layer_set_layer:
    PROLOGUE
    ASSERT_PTR rdi
    cmp rsi, 5
    ja .invalid
    mov dword [rdi + Layer.layer], esi
    xor rax, rax
    leave
    ret

.invalid:
    mov rax, -(EINVAL)
    leave
    ret

; ---------------------------------------------------------------------------
; layer_set_namespace
; ---------------------------------------------------------------------------
global layer_set_namespace
layer_set_namespace:
    PROLOGUE
    ASSERT_PTR rdi
    mov [rdi + Layer.namespace], rsi
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; layer_set_anchor
; ---------------------------------------------------------------------------
global layer_set_anchor
layer_set_anchor:
    PROLOGUE
    ASSERT_PTR rdi
    mov dword [rdi + Layer.anchor], esi
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; layer_set_exclusive_zone
;   Set exclusive zone (for panels - reserves space)
; ---------------------------------------------------------------------------
global layer_set_exclusive_zone
layer_set_exclusive_zone:
    PROLOGUE
    ASSERT_PTR rdi
    mov dword [rdi + Layer.exclusive_zone], esi
    ; TODO: Notify policy for layout recalculation
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; layer_set_margin
; ---------------------------------------------------------------------------
global layer_set_margin
layer_set_margin:
    PROLOGUE
    ASSERT_PTR rdi
    mov dword [rdi + Layer.margin_top], esi
    mov dword [rdi + Layer.margin_bottom], edx
    mov dword [rdi + Layer.margin_left], ecx
    mov dword [rdi + Layer.margin_right], r8d
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; layer_set_keyboard_interactivity
; ---------------------------------------------------------------------------
global layer_set_keyboard_interactivity
layer_set_keyboard_interactivity:
    PROLOGUE
    ASSERT_PTR rdi
    cmp rsi, 2
    ja .invalid
    mov byte [rdi + Layer.keyboard_interactivity], sil
    leave
    ret

.invalid:
    mov rax, -(EINVAL)
    leave
    ret

; ---------------------------------------------------------------------------
; layer_get_geometry
;   Compute layer geometry based on anchors, margins, exclusive zone
; ---------------------------------------------------------------------------
global layer_get_geometry
layer_get_geometry:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi  ; output rect
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov eax, [rbx + Layer.layer]
    ; TODO: Compute based on layer level, anchors, margins, exclusive zone

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data


global layer_version
layer_version: dq 0x010000
