; =============================================================================
; Utkarsha OS — lib/ugfx/include/ugfx.inc
; =============================================================================
; Public definitions for the ugfx graphics library: calling-convention macros,
; error codes, and the layouts of the objects ugfx functions take and return.
; This header is the single source for these layouts; other libraries include
; it instead of redefining them.
;
; ugfx owns no math: geometry and fixed-point arithmetic belong to lib/umath.
; Memory comes from the caller's arena through `arena_alloc` (rdi = arena,
; rsi = size -> rax = pointer or 0), treated as an opaque handle.
; =============================================================================

%ifndef __UGFX_INC__
%define __UGFX_INC__

; -----------------------------------------------------------------------------
; Calling convention (System V register order, callee-saved rbx/rbp/r12-r15).
; Defined only if the including program has not defined them already.
; -----------------------------------------------------------------------------
%ifnmacro PROLOGUE 0
%macro PROLOGUE 0
    push rbp
    mov  rbp, rsp
%endmacro
%endif

%ifnmacro EPILOGUE 0
%macro EPILOGUE 0
    leave
    ret
%endmacro
%endif

%ifnmacro PROLOGUE_SAVE 1-*
%macro PROLOGUE_SAVE 1-*
    push rbp
    mov  rbp, rsp
    %rep %0
        push %1
        %rotate 1
    %endrep
%endmacro
%endif

%ifnmacro EPILOGUE_RESTORE 1-*
%macro EPILOGUE_RESTORE 1-*
    %rep %0
        %rotate -1
        pop %1
    %endrep
    leave
    ret
%endmacro
%endif

; Debug-build pointer check; the program provides panic_null_ptr.
%ifndef DEBUG_BUILD
    %define DEBUG_BUILD 0
%endif
%ifnmacro ASSERT_PTR 1
%macro ASSERT_PTR 1
    %if DEBUG_BUILD
        test %1, %1
        jnz %%ok
        call panic_null_ptr
    %%ok:
    %endif
%endmacro
%endif
%if DEBUG_BUILD
extern panic_null_ptr
%endif

; -----------------------------------------------------------------------------
; Error codes (returned negated)
; -----------------------------------------------------------------------------
%ifndef ENOMEM
    %define ENOMEM      12
%endif
%ifndef EINVAL
    %define EINVAL      22
%endif
%ifndef ENOSPC
    %define ENOSPC      28
%endif
%ifndef ENOTSUP
    %define ENOTSUP     95
%endif

; -----------------------------------------------------------------------------
; PixBuf — pixel buffer, 32-bit premultiplied BGRA unless format says otherwise
; -----------------------------------------------------------------------------
%define PixBuf_width        0           ; u64 pixels
%define PixBuf_height       8           ; u64 pixels
%define PixBuf_stride       16          ; u64 bytes per row
%define PixBuf_format       24          ; u64 pixel format code
%define PixBuf_data         32          ; u64 pointer to the first row
%define PixBuf_size         40          ; u64 bytes of pixel data
%define PixBuf_refcount     48          ; u64
%define PixBuf_arena        56          ; u64 arena the buffer came from
%define PixBuf_size_total   64          ; size of the object

; -----------------------------------------------------------------------------
; Rect — half-open integer rectangle [x1, x2) x [y1, y2)
; -----------------------------------------------------------------------------
%define Rect_x1             0           ; i32
%define Rect_y1             4           ; i32
%define Rect_x2             8           ; i32
%define Rect_y2             12          ; i32
%define Rect_size           16

; -----------------------------------------------------------------------------
; Region — set of non-overlapping rectangles
; -----------------------------------------------------------------------------
%define Region.rects        0           ; Rect*
%define Region.count        8           ; u64
%define Region.capacity     16          ; u64
%define Region.arena        24          ; arena for growth
%define Region_SIZE         32

; -----------------------------------------------------------------------------
; Buffer transforms (transform_*)
; -----------------------------------------------------------------------------
%define TRANSFORM_NORMAL    0
%define TRANSFORM_90        1
%define TRANSFORM_180       2
%define TRANSFORM_270       3
%define TRANSFORM_FLIP_H    4
%define TRANSFORM_FLIP_V    8

; -----------------------------------------------------------------------------
; 2D paths
; -----------------------------------------------------------------------------
%define PATH_MAX_VERBS      2048
%define PATH_MAX_POINTS     (PATH_MAX_VERBS * 4)
%define PATH_VERB_MOVE      0
%define PATH_VERB_LINE      1
%define PATH_VERB_QUAD      2
%define PATH_VERB_CUBIC     3
%define PATH_VERB_ARC       4
%define PATH_VERB_CLOSE     5
%define PATH_VERB_END       255

%endif ; __UGFX_INC__
