; ============================================================================
; GPU Interface — Backend-Agnostic GPU Abstraction (one family at a time)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/canvas_client.inc"

extern arena_alloc
extern gpu_mem_init
extern gpu_fence_init
extern gpu_ring_init

; struct offsets (hoisted above use)
%define GpuDevice_SIZE    72
%define GPU_FAMILY_UNKNOWN   0
%define GPU_FAMILY_GFX9      0x0900
%define GPU_FAMILY_GFX10     0x0A00
%define GPU_FAMILY_GFX11     0x0B00
%define GPU_RING_GFX        0
%define GPU_RING_COMPUTE    1
%define GPU_RING_SDMA       2

section .text

; GpuDevice struct layout (manual offsets to avoid NASM preprocessor issues)
; Offsets defined in inc/struct_offsets.inc

; ------------------


; ---------------------------------------------------------------------------
; gpu_init
;   IN: rdi = server*, rsi = arena — discovers GPU via ut_pci, maps BARs
; ---------------------------------------------------------------------------
global gpu_init
gpu_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Server.arena]
    mov rsi, GpuDevice_size
    mov r12, rbx
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov qword [rbx + GpuDevice.server], r12
    mov dword [rbx + GpuDevice.family], GPU_FAMILY_UNKNOWN
    mov qword [rbx + GpuDevice.mmio_base], 0
    mov qword [rbx + GpuDevice.mmio_size], 0
    mov qword [rbx + GpuDevice.ring_gfx], 0
    mov qword [rbx + GpuDevice.ring_compute], 0
    mov qword [rbx + GpuDevice.ring_sdma], 0
    mov qword [rbx + GpuDevice.mem_mgr], 0
    mov qword [rbx + GpuDevice.fence_mgr], 0
    mov byte [rbx + GpuDevice.enabled], 0
    mov qword [r12 + Server.gpu], rbx
    ; discover 3D controller (class 0x03 subclass 0x02)
    mov rdi, GPU_CLASS_DISPLAY
    mov rsi, GPU_SUBCLASS_3D
    call ut_pci_find_class
    test rax, rax
    jz .no_gpu
    ; found: enable + map BAR0 (MMIO), BAR2 (VRAM aperture)
    mov [rbx + GpuDevice.mem], rax
    mov rdi, rax
    call ut_pci_enable_device
    mov [rbx + GpuDevice.enabled], byte 1
    ; detect family from device id
    mov rdi, rbx
    call gpu_detect_family
    ; init submodules
    mov rdi, [rbx + GpuDevice.server]
    mov rsi, rbx
    call gpu_mem_init
    mov rdi, [rbx + GpuDevice.server]
    mov rsi, rbx
    call gpu_fence_init
    mov rdi, [rbx + GpuDevice.server]
    mov rsi, rbx
    mov rdx, GPU_RING_GFX
    call gpu_ring_init
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.no_gpu:
    ; no GPU: software path stays active; not fatal
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; gpu_detect_family
; ---------------------------------------------------------------------------
gpu_detect_family:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov rdi, [rbx + GpuDevice.mem]
    xor esi, esi
    call ut_pci_config_read_dword
    test rax, rax
    js .unsupported
    mov edx, eax
    and eax, 0xffff
    cmp eax, 0x1002
    jne .unsupported
    shr edx, 16
    cmp edx, 0x7400
    jae .gfx11
    cmp edx, 0x7300
    jae .gfx10
    cmp edx, 0x6600
    jae .gfx9
.unsupported:
    mov dword [rbx + GpuDevice.family], GPU_FAMILY_UNKNOWN
    mov rax, -(ENODEV)
    EPILOGUE_RESTORE rbx
    ret
.gfx11:
    mov dword [rbx + GpuDevice.family], GPU_FAMILY_GFX11
    jmp .ok
.gfx10:
    mov dword [rbx + GpuDevice.family], GPU_FAMILY_GFX10
    jmp .ok
.gfx9:
    mov dword [rbx + GpuDevice.family], GPU_FAMILY_GFX9
.ok:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; gpu_shutdown
; ---------------------------------------------------------------------------
global gpu_shutdown
gpu_shutdown:
    PROLOGUE
    ASSERT_PTR rdi
    mov byte [rdi + GpuDevice.enabled], 0
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; gpu_is_available
; ---------------------------------------------------------------------------
global gpu_is_available
gpu_is_available:
    PROLOGUE
    ASSERT_PTR rdi
    movzx rax, byte [rdi + GpuDevice.enabled]
    leave
    ret

section .rodata
GPU_CLASS_DISPLAY:   dd 0x03
GPU_SUBCLASS_3D:     dd 0x02

section .data
global gpu_version
gpu_version: dq 0x010000
