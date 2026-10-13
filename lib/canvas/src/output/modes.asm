; ============================================================================
; Modes — Display Mode Management (Modeline Parsing, CVT, GTF)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/fixed.inc"

; struct offsets (hoisted above use)
%define Mode_width          0
%define Mode.width 0
%define Mode_height         4
%define Mode.height 4
%define Mode_htotal         8
%define Mode.htotal 8
%define Mode_hsync_start    12
%define Mode.hsync_start 12
%define Mode_hsync_end      16
%define Mode.hsync_end 16
%define Mode_vtotal         20
%define Mode.vtotal 20
%define Mode_vsync_start    24
%define Mode.vsync_start 24
%define Mode_vsync_end      28
%define Mode.vsync_end 28
%define Mode_flags          32
%define Mode.flags 32
%define Mode_pixel_clock    36
%define Mode.pixel_clock 36
%define Mode_refresh_ns     40
%define Mode.refresh_ns 40
%define Mode_width_mm       48
%define Mode_height_mm      52
%define Mode_hborder        56
%define Mode_vborder        57
%define Mode_hsync_offset   58
%define Mode.hsync_offset 58
%define Mode_hsync_width    60
%define Mode.hsync_width 60
%define Mode_vsync_offset   62
%define Mode.vsync_offset 62
%define Mode_vsync_width    63
%define Mode.vsync_width 63
%define Mode_size           64
%define MODE_FLAG_HSYNC_POSITIVE   (1 << 0)
%define MODE_FLAG_VSYNC_POSITIVE   (1 << 1)
%define MODE_FLAG_INTERLACED       (1 << 2)
%define MODE_FLAG_PREFERRED        (1 << 3)
%define MODE_FLAG_VRR              (1 << 4)

section .text



; ---------------------------------------------------------------------------
; mode_init
;   Initialize mode from parameters
;   IN:  rdi = Mode*, rsi = width, rdx = height, rcx = refresh_hz
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global mode_init
mode_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    ASSERT_PTR rbx

    mov [rbx + Mode.width], r12d
    mov [rbx + Mode.height], r13d

    ; Calculate CVT timing
    call mode_calc_cvt

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; mode_calc_cvt
;   Calculate CVT (Coordinated Video Timings) mode
;   IN:  rbx = Mode*, r12 = width, r13 = height
;   OUT: Mode filled with CVT timing
; ---------------------------------------------------------------------------
mode_calc_cvt:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx

    ; CVT Reduced Blanking v2 calculation
    ; Simplified - use standard values for common resolutions
    cmp r12d, 1920
    jne .not_1080p
    cmp r13d, 1080
    jne .not_1080p

    ; 1920x1080@60Hz CVT-RBv2
    mov dword [rdi + Mode.htotal], 2080
    mov dword [rdi + Mode.hsync_start], 1968
    mov dword [rdi + Mode.hsync_end], 2000
    mov dword [rdi + Mode.vtotal], 1111
    mov dword [rdi + Mode.vsync_start], 1083
    mov dword [rdi + Mode.vsync_end], 1089
    mov dword [rdi + Mode.flags], MODE_FLAG_HSYNC_POSITIVE | MODE_FLAG_VSYNC_POSITIVE
    mov dword [rdi + Mode.pixel_clock], 138500  ; kHz
    mov qword [rdi + Mode.refresh_ns], 16666667
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.not_1080p:
    cmp r12d, 3840
    jne .not_4k
    cmp r13d, 2160
    jne .not_4k

    ; 3840x2160@60Hz
    mov dword [rdi + Mode.htotal], 4400
    mov dword [rdi + Mode.hsync_start], 4008
    mov dword [rdi + Mode.hsync_end], 4080
    mov dword [rdi + Mode.vtotal], 2250
    mov dword [rdi + Mode.vsync_start], 2168
    mov dword [rdi + Mode.vsync_end], 2178
    mov dword [rdi + Mode.flags], MODE_FLAG_HSYNC_POSITIVE | MODE_FLAG_VSYNC_POSITIVE
    mov dword [rdi + Mode.pixel_clock], 533250
    mov qword [rdi + Mode.refresh_ns], 16666667
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.not_4k:
    cmp r12d, 2560
    jne .not_1440p
    cmp r13d, 1440
    jne .not_1440p

    ; 2560x1440@60Hz
    mov dword [rdi + Mode.htotal], 2720
    mov dword [rdi + Mode.hsync_start], 2608
    mov dword [rdi + Mode.hsync_end], 2640
    mov dword [rdi + Mode.vtotal], 1481
    mov dword [rdi + Mode.vsync_start], 1443
    mov dword [rdi + Mode.vsync_end], 1449
    mov dword [rdi + Mode.flags], MODE_FLAG_HSYNC_POSITIVE | MODE_FLAG_VSYNC_POSITIVE
    mov dword [rdi + Mode.pixel_clock], 241500
    mov qword [rdi + Mode.refresh_ns], 16666667
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.not_1440p:
    ; Default: 640x480@60Hz
    mov dword [rdi + Mode.htotal], 800
    mov dword [rdi + Mode.hsync_start], 656
    mov dword [rdi + Mode.hsync_end], 752
    mov dword [rdi + Mode.vtotal], 525
    mov dword [rdi + Mode.vsync_start], 490
    mov dword [rdi + Mode.vsync_end], 492
    mov dword [rdi + Mode.flags], MODE_FLAG_HSYNC_POSITIVE | MODE_FLAG_VSYNC_POSITIVE
    mov dword [rdi + Mode.pixel_clock], 25175
    mov qword [rdi + Mode.refresh_ns], 16666667
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; mode_from_edid
;   Create mode from EDID detailed timing
;   IN:  rdi = Mode*, rsi = edid_timing* (18 bytes)
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global mode_from_edid
mode_from_edid:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Pixel clock (10kHz units)
    mov ax, [r12]
    mov [rbx + Mode.pixel_clock], eax

    ; Horizontal active
    mov al, [r12 + 2]
    mov ah, [r12 + 4]
    and ah, 0xF0
    shr ah, 4
    mov [rbx + Mode.width], ax

    ; Horizontal blanking
    mov al, [r12 + 3]
    mov ah, [r12 + 4]
    and ah, 0x0F
    mov [rbx + Mode.hblank], ax

    ; Vertical active
    mov al, [r12 + 5]
    mov ah, [r12 + 7]
    and ah, 0xF0
    shr ah, 4
    mov [rbx + Mode.height], ax

    ; Vertical blanking
    mov al, [r12 + 6]
    mov ah, [r12 + 7]
    and ah, 0x0F
    mov [rbx + Mode.vblank], ax

    ; HSync offset
    mov al, [r12 + 8]
    mov ah, [r12 + 10]
    and ah, 0xF0
    shr ah, 4
    mov [rbx + Mode.hsync_offset], ax

    ; HSync width
    mov al, [r12 + 9]
    mov ah, [r12 + 10]
    and ah, 0x0F
    mov [rbx + Mode.hsync_width], ax

    ; VSync offset
    mov al, [r12 + 11]
    mov ah, [r12 + 10]
    and ah, 0xC0
    shr ah, 6
    mov [rbx + Mode.vsync_offset], ax

    ; VSync width
    mov al, [r12 + 11]
    and al, 0x30
    shr al, 4
    mov [rbx + Mode.vsync_width], al

    ; Compute totals
    mov ax, [rbx + Mode.width]
    add ax, [rbx + Mode.hblank]
    mov [rbx + Mode.htotal], ax

    mov al, [rbx + Mode.hsync_offset]
    add ax, [rbx + Mode.hsync_width]
    mov [rbx + Mode.hsync_start], ax

    mov ax, [rbx + Mode.hsync_start]
    add ax, [rbx + Mode.hsync_width]
    mov [rbx + Mode.hsync_end], ax

    mov ax, [rbx + Mode.height]
    add ax, [rbx + Mode.vblank]
    mov [rbx + Mode.vtotal], ax

    mov al, [rbx + Mode.vsync_offset]
    add ax, [rbx + Mode.vsync_width]
    mov [rbx + Mode.vsync_start], ax

    mov al, [rbx + Mode.vsync_offset]
    add al, [rbx + Mode.vsync_width]
    mov [rbx + Mode.vsync_end], al

    ; Pixel clock to refresh rate
    ; refresh = pixel_clock / (htotal * vtotal) * 1000
    mov eax, [rbx + Mode.pixel_clock]
    mov ecx, [rbx + Mode.htotal]
    imul ecx, [rbx + Mode.vtotal]
    div ecx
    mov ebx, 1000000000
    div eax
    mov [rbx + Mode.refresh_ns], rax

    ; Flags from EDID
    mov al, [r12 + 17]
    mov [rbx + Mode.flags], al

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; mode_validate
;   Validate mode parameters
; ---------------------------------------------------------------------------
global mode_validate
mode_validate:
    PROLOGUE
    ASSERT_PTR rdi

    ; Check dimensions
    mov eax, [rdi + Mode.width]
    test eax, eax
    jz .fail
    cmp eax, 32768
    ja .fail

    mov eax, [rdi + Mode.height]
    test eax, eax
    jz .fail
    cmp eax, 32768
    ja .fail

    ; Check totals > active
    mov eax, [rdi + Mode.htotal]
    cmp eax, [rdi + Mode.width]
    jbe .fail

    mov eax, [rdi + Mode.vtotal]
    cmp eax, [rdi + Mode.height]
    jbe .fail

    ; Check sync within totals
    mov eax, [rdi + Mode.hsync_end]
    cmp eax, [rdi + Mode.htotal]
    ja .fail

    mov eax, [rdi + Mode.vsync_end]
    cmp eax, [rdi + Mode.vtotal]
    ja .fail

    xor rax, rax
    leave
    ret

.fail:
    mov rax, -(EINVAL)
    leave
    ret

; ---------------------------------------------------------------------------
; mode_equal
;   Compare two modes
; ---------------------------------------------------------------------------
global mode_equal
mode_equal:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi

    mov eax, [rdi + Mode.width]
    cmp eax, [rsi + Mode.width]
    jne .diff

    mov eax, [rdi + Mode.height]
    cmp eax, [rsi + Mode.height]
    jne .diff

    mov eax, [rdi + Mode.pixel_clock]
    cmp eax, [rsi + Mode.pixel_clock]
    jne .diff

    mov rax, [rdi + Mode.flags]
    cmp rax, [rsi + Mode.flags]
    jne .diff

    mov rax, 1
    leave
    ret

.diff:
    xor rax, rax
    leave
    ret

section .data
global modes_version
modes_version: dq 0x010000
