; ============================================================================
; Cursor — Cursor Image and Theme Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/pixbuf.inc"
%include "inc/image.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"

extern arena_alloc
extern pixbuf_create
extern cursor_theme_load
extern cursor_theme_get_cursor

; struct offsets (hoisted above use)
%define Cursor_SIZE 48
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

; Cursor struct layout (manual offsets)\n; Offsets defined in inc/struct_offsets.inc\n\n; ----------\n
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

    ; Always provide a built-in theme; disk themes can override it later.
    call cursor_create_default
    test rax, rax
    jz .fail

    ; Store as default
    mov qword [rbx + Server.cursors], rax
    mov rdi, rbx
    lea rsi, [rel default_theme_name]
    call cursor_theme_load
    test rax, rax
    jz .fail
    mov [rbx + Server.cursor_theme], rax

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

    mov rdi, [rbx + PixBuf.data]
    xor eax, eax
    mov ecx, 32 * 32
    rep stosd
    mov rdi, [rbx + PixBuf.data]
    xor ecx, ecx
.arrow_row:
    cmp ecx, 24
    jae .arrow_done
    mov edx, ecx
    shr edx, 1
    add edx, 2
    xor esi, esi
.arrow_col:
    cmp esi, edx
    jae .arrow_next
    mov eax, 0xffffffff
    test esi, esi
    jz .arrow_border
    lea r8d, [rdx - 1]
    cmp esi, r8d
    jne .arrow_store
.arrow_border:
    mov eax, 0xff000000
.arrow_store:
    mov [rdi + rsi * 4], eax
    inc esi
    jmp .arrow_col
.arrow_next:
    add rdi, 128
    inc ecx
    jmp .arrow_row
.arrow_done:

    ; Create cursor object
    mov rdi, r12
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
    PROLOGUE_SAVE rbx, r12, r13, r14
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

    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.bad_hotspot:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; cursor_set_theme
; ---------------------------------------------------------------------------
global cursor_set_theme
cursor_set_theme:
    PROLOGUE
    test rsi, rsi
    jz .theme_bad
    mov [rdi + Server.cursor_theme], rsi
    xor rax, rax
    leave
    ret
.theme_bad:
    mov rax, -(EINVAL)
    leave
    ret

; ---------------------------------------------------------------------------
; cursor_get
;   Get cursor by name
; ---------------------------------------------------------------------------
global cursor_get
cursor_get:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    mov rdi, [rbx + Server.cursor_theme]
    test rdi, rdi
    jz .cursor_builtin
    call cursor_theme_get_cursor
    EPILOGUE_RESTORE rbx
    ret
.cursor_builtin:
    mov rax, [rbx + Server.cursors]
    EPILOGUE_RESTORE rbx
    ret

section .rodata
default_theme_name: db "default",0

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
