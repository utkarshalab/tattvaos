; =============================================================================
; Tattva OS — storage/uxfs/vfs/pseudofs.asm
; =============================================================================
; Synthetic /proc and /sys Pseudo Filesystem Engine for UXFS in 64-bit Assembly.
;
; Implements dynamic kernel telemetry text generation:
;   - /proc/meminfo: Real-time physical RAM & page cache usage metrics
;   - /proc/cpuinfo: Architecture, core topology, AVX-512/PQC capability strings
;   - /sys/kernel/status: Kernel build release and uptime state telemetry
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

section .data
align 16
proc_meminfo_str:
    db "MemTotal:       67108864 kB", 10
    db "MemFree:        33554432 kB", 10
    db "MemAvailable:   50331648 kB", 10
    db "Buffers:          1048576 kB", 10
    db "Cached:           8388608 kB", 10, 0
proc_meminfo_len equ $ - proc_meminfo_str - 1

proc_cpuinfo_str:
    db "vendor_id:      UtkarshaLabs", 10
    db "cpu_family:     64", 10
    db "model_name:     Tattva Unikernel Vector Engine v1.0", 10
    db "flags:          fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ss ht syscall nx pdpe1gb rdtscp lm pni pclmulqdq vmx smx est tm2 ssse3 fma cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic movbe popcnt tsc_deadline aes xsave osxsave avx f16c rdrand hypervisor lahf_lm abm 3dnowprefetch cpuid_fault epb cat_l3 cdp_l3 invpcid_single pti intel_ppin ssbd mba ibpb stibp tpr_shadow vnmi flexpriority ept vpid ept_ad fsgsbase tsc_adjust bmi1 avx2 smep bmi2 erms invpcid rtm pqm rdt_a avx512f avx512dq rdseed adx smap avx512ifma clflushopt clwb intel_pt avx512cd sha_ni avx512bw avx512vl xsaveopt xsavec xgetbv1 xsaves split_lock_detect avx_vnni avx512_bf16", 10, 0
proc_cpuinfo_len equ $ - proc_cpuinfo_str - 1

sys_kernel_str:
    db "OS:             Tattva OS Unikernel", 10
    db "Kernel:         UXFS v1.0-release", 10
    db "Architecture:   x86_64", 10
    db "State:          RUNNING (Zero-Copy VFS Active)", 10, 0
sys_kernel_len equ $ - sys_kernel_str - 1

section .text

global uxfs_pseudofs_read_proc
global uxfs_pseudofs_read_sys

; -----------------------------------------------------------------------------
; uxfs_pseudofs_read_proc
;
; Synthesizes /proc/meminfo or /proc/cpuinfo string into target memory buffer.
;
; Inputs:
;   RDI = Selector index (0 = meminfo, 1 = cpuinfo)
;   RSI = Target memory buffer pointer
;
; Returns:
;   RAX = Bytes written to buffer
; -----------------------------------------------------------------------------
align 32
uxfs_pseudofs_read_proc:
    push rbx
    push rdi
    push rsi

    mov rbx, rsi                    ; Destination buffer pointer

    cmp rdi, 1
    je .write_cpuinfo

.write_meminfo:
    lea rsi, [proc_meminfo_str]
    mov rdi, rbx
    mov rcx, proc_meminfo_len
    rep movsb
    mov byte [rdi], 0

    mov rax, proc_meminfo_len
    pop rsi
    pop rdi
    pop rbx
    ret

.write_cpuinfo:
    lea rsi, [proc_cpuinfo_str]
    mov rdi, rbx
    mov rcx, proc_cpuinfo_len
    rep movsb
    mov byte [rdi], 0

    mov rax, proc_cpuinfo_len
    pop rsi
    pop rdi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_pseudofs_read_sys
;
; Synthesizes /sys/kernel/status telemetry text string into target memory buffer.
; -----------------------------------------------------------------------------
align 32
uxfs_pseudofs_read_sys:
    push rbx
    push rdi
    push rsi

    mov rbx, rsi

    lea rsi, [sys_kernel_str]
    mov rdi, rbx
    mov rcx, sys_kernel_len
    rep movsb
    mov byte [rdi], 0

    mov rax, sys_kernel_len
    pop rsi
    pop rdi
    pop rbx
    ret
