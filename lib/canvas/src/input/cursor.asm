; ============================================================================
; Cursor — Cursor Image and Theme Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/pixbuf.inc"

; struct offsets (hoisted above use)
%define Cursor_size    48
%define CURSOR_DEFAULT      0
%define CURSOR_TEXT         1
%define CURSOR_POINTER      2
%define CURSOR_CROSSHAIR    3
%define CURSOR_HAND         4
%define CURSOR_HELP         5
%define CURSOR_WAIT         6
%define CURSOR_PROGRESS     7
%define CURSOR_NESW_RESIZE  8
%define CURSOR_NS_RESIZE    9
%define CURSOR_NWSE_RESIZE  10
%define CURSOR_EW_RESIZE    11
%define CURSOR_COL_RESIZE   12
%define CURSOR_ROW_RESIZE   13
%define CURSOR_ALL_SCROLL   14
%define CURSOR_NOT_ALLOWED  15
%define CURSOR_COPY         16
%define CURSOR_MOVE         17
%define CURSOR_LINK         18
%define CURSOR_CELL         19
%define CURSOR_VERTICAL_TEXT 20
%define CURSOR_ALIAS        21
%define CURSOR_CONTEXT_MENU 22
%define CURSOR_GRAB         23
%define CURSOR_GRABBING     24
%define CURSOR_ZOOM_IN      25
%define CURSOR_ZOOM_OUT     26

section .text

struc Cursor
    .name:          resq 1
    .pixbuf:        resq 1
    .hotspot_x:     resd 1
    .hotspot_y:     resd 1
    .delay:         resd 1  ; for animated cursors
    .next_frame:    resq 1
endstruc


; ---------------------------------------------------------------------------
; cursor_init
; ---------------------------------------------------------------------------
global cursor_init
cursor_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.cursors], 0
    mov qword [rbx + Server.cursor_theme], 0
    mov qword [rbx + Server.arena], r12

    ; Load default cursor theme
    call cursor_load_theme

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; cursor_load_theme
;   Load cursor theme from directory
; ---------------------------------------------------------------------------
cursor_load_theme:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; TODO: Read cursor theme from directory
    ; For now, create default cursors

    ; Create default cursor shapes using pixbuf
    ; CURSOR_DEFAULT - arrow
    call cursor_create_default
    test rax, rax
    jz .fail

    ; Store as default
    mov qword [rbx + Server.cursors], rax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.fail:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; cursor_create_default
;   Create default cursor shapes programmatically
; ---------------------------------------------------------------------------
cursor_create_default:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Create arrow cursor (32x32)
    mov rdi, r12
    mov rsi, 32
    mov rdx, 32
    mov rcx, DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax, rax
    jz .fail
    mov rbx, rax

    ; Draw arrow shape
    ; TODO: Draw actual arrow shape
    ; For now, fill with white
    mov rdi, [rbx + PixBuf.data]
    mov rsi, 0xFFFFFFFF
    mov rdx, 32
    mov rcx, 32
    mov r8, 128
    call fill_solid

    ; Create cursor object
    mov rdi, [r12 + Server.arena]
    mov rsi, Cursor_size
    call arena_alloc
    test rax, rax
    jz .fail

    mov qword [rax + Cursor.pixbuf], rbx
    mov dword [rax + Cursor.hotspot_x], 0
    mov dword [rax + Cursor.hotspot_y], 0
    mov dword [rax + Cursor.delay], 0
    mov qword [rax + Cursor.next_frame], 0

    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.fail:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; cursor_create_from_pixbuf
;   Create cursor from pixbuf
; ---------------------------------------------------------------------------
global cursor_create_from_pixbuf
cursor_create_from_pixbuf:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Validate hotspot within pixbuf
    mov eax, [r12 + PixBuf.width]
    cmp r13d, eax
    jae .bad_hotspot
    mov eax, [r12 + PixBuf.height]
    cmp r14d, eax
    jae .bad_hotspot

    mov rdi, [rbx + Server.arena]
    mov rsi, Cursor_size
    call arena_alloc
    test rax, rax
    jz .oom

    mov qword [rax + Cursor.pixbuf], r12
    mov dword [rax + Cursor.hotspot_x], r13d
    mov dword [rax + Cursor.hotspot_y], r14d
    mov dword [rax + Cursor.delay], 0
    mov qword [rax + Cursor.next_frame], 0

    EPILOGUE_RESTORE rbx, r12, r13
    ret

.bad_hotspot:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; cursor_set_theme
; ---------------------------------------------------------------------------
global cursor_set_theme
cursor_set_theme:
    PROLOGUE
    ; TODO
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; cursor_get
;   Get cursor by name
; ---------------------------------------------------------------------------
global cursor_get
cursor_get:
    PROLOGUE
    ; TODO: Lookup cursor by name
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; cursor_set_image
;   Set cursor image for surface
; ---------------------------------------------------------------------------
global cursor_set_image
cursor_set_image:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Cursor.current], r12
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global cursor_version
cursor_version: dq 0x010000
