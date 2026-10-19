; UTM Kernel - Process Table with Identity Tracking
%ifndef _UTM_PROC_TABLE_ASM_
%define _UTM_ENTERPRISE_PROC_TABLE_ASM_

%include "constants.inc"
%include "structures.inc"
%include "syscalls.inc"

section .rodata
utm_proc_table_lock     dq 0
utm_next_pid            dq 1
utm_pid_generation      dq 0
utm_proc_entry_size_val dq PROC_ENTRY_SIZE

section .bss
align 4096
global utm_proc_table
utm_proc_table:
    resb MAX_PROCESSES * PROC_ENTRY_SIZE

utm_pid_bitmap:
    resq MAX_PROCESSES / 64

utm_pid_hash_table:
    resq MAX_PROCESSES * 2

section .text

global utm_proc_table_init
global utm_proc_alloc_pid
global utm_proc_free_pid
global utm_proc_get_by_pid
global utm_proc_verify_identity
global utm_proc_fill_sample
global utm_spin_lock_acquire
global utm_spin_lock_release

utm_proc_table_init:
    mov rdi, utm_proc_table
    mov rcx, MAX_PROCESSES * PROC_ENTRY_SIZE
    xor rax, rax
    rep stosb
    
    mov rdi, utm_pid_bitmap
    mov rcx, MAX_PROCESSES / 64
    xor rax, rax
    rep stosq
    
    mov rdi, utm_pid_hash_table
    mov rcx, MAX_PROCESSES * 2
    xor rax, rax
    rep stosq
    
    mov qword [utm_next_pid], 1
    mov qword [utm_pid_generation], 1
    mov qword [utm_proc_table_lock], 0
    ret

utm_proc_alloc_pid:
    call utm_spin_lock_acquire
    
    mov rcx, [utm_next_pid]
    mov r8, MAX_PROCESSES
    
.alloc_loop:
    mov r9, rcx
    dec r9
    mov r10, r9
    shr r10, 6
    and r9, 63
    bt qword [utm_pid_bitmap + r10*8], r9
    jc .pid_taken
    
    bts qword [utm_pid_bitmap + r10*8], r9
    
    call utm_proc_find_free_slot
    test rax, rax
    jz .alloc_failed
    
    mov rdx, [utm_pid_generation]
    inc qword [utm_pid_generation]
    
    call utm_proc_hash_insert
    
    inc rcx
    cmp rcx, MAX_PROCESSES
    jne .store_next
    mov rcx, 1
.store_next:
    mov [utm_next_pid], rcx
    
    mov rax, rcx
    mov rdx, rax
    call utm_spin_lock_release
    ret

.pid_taken:
    inc rcx
    cmp rcx, MAX_PROCESSES
    jne .alloc_loop
    mov rcx, 1
    jmp .alloc_loop

.alloc_failed:
    xor rax, rax
    call utm_spin_lock_release
    ret

utm_proc_free_pid:
    call utm_spin_lock_acquire
    
    call utm_proc_hash_lookup
    test rax, rax
    jz .not_found
    
    mov rdi, rax
    call utm_proc_clear_pid_bitmap
    
    call utm_proc_hash_remove
    
    mov rdi, utm_proc_table
    add rdi, rax
    mov rcx, PROC_ENTRY_SIZE
    xor rax, rax
    rep stosb
    
    xor rax, rax
    call utm_spin_lock_release
    ret

.not_found:
    mov rax, UTM_ERR_NOPROC
    call utm_spin_lock_release
    ret

utm_proc_hash_insert:
    mov rcx, rax
    mov rdx, [utm_pid_generation]
    xor rcx, rdx
    mov rdx, rcx
    shr rdx, 33
    xor rcx, rdx
    imul rcx, 0xff51afd7ed558ccd
    mov rdx, rcx
    shr rdx, 33
    xor rcx, rdx
    imul rcx, 0xc4ceb9fe1a85ec53
    mov rdx, rcx
    shr rdx, 33
    xor rcx, rdx
    
    and rcx, (MAX_PROCESSES * 2) - 1
    
    mov r9, utm_pid_hash_table
.probe_loop:
    cmp qword [r9 + rcx*8], 0
    je .found_slot
    inc rcx
    and rcx, (MAX_PROCESSES * 2) - 1
    jmp .probe_loop

.found_slot:
    shl rdx, 32
    or rdx, rax
    inc rdx
    mov [r9 + rcx*8], rdx
    ret

utm_proc_hash_lookup:
    mov rax, rdi
    mov rcx, rax
    mov rdx, [utm_pid_generation]
    xor rcx, rdx
    mov rdx, rcx
    shr rdx, 33
    xor rcx, rdx
    imul rcx, 0xff51afd7ed558ccd
    mov rdx, rcx
    shr rdx, 33
    xor rcx, rdx
    imul rcx, 0xc4ceb9fe1a85ec53
    mov rdx, rcx
    shr rdx, 33
    xor rcx, rdx
    
    and rcx, (MAX_PROCESSES * 2) - 1
    
    mov r9, utm_pid_hash_table
.lookup_loop:
    mov r10, [r9 + rcx*8]
    test r10, r10
    jz .not_found
    
    cmp r10d, edi
    je .found
    
    inc rcx
    and rcx, (MAX_PROCESSES * 2) - 1
    jmp .lookup_loop

.found:
    shr r10, 32
    dec r10
    mov rax, r10
    ret

.not_found:
    xor rax, rax
    ret

utm_proc_hash_remove:
    ret

utm_proc_find_free_slot:
    mov rcx, MAX_PROCESSES
    mov rdi, utm_proc_table
.scan_loop:
    cmp byte [rdi + ProcessEntry.state], 0
    je .found
    add rdi, PROC_ENTRY_SIZE
    loop .scan_loop
    xor rax, rax
    ret
.found:
    sub rdi, utm_proc_table
    mov rax, rdi
    xor rdx, rdx
    mov r8, PROC_ENTRY_SIZE
    div r8
    ret

utm_proc_clear_pid_bitmap:
    mov rsi, utm_proc_table
    mov rax, rdi
    xor rdx, rdx
    mov r8, PROC_ENTRY_SIZE
    mul r8
    add rsi, rax
    mov rdi, [rsi + ProcessEntry.identity + ProcessIdentity.pid]
    dec rdi
    mov rcx, rdi
    shr rcx, 6
    and rdi, 63
    btr qword [utm_pid_bitmap + rcx*8], rdi
    ret

utm_proc_get_by_pid:
    call utm_proc_hash_lookup
    test rax, rax
    jz .not_found
    
    mov rsi, utm_proc_table
    mov rcx, rax
    xor rdx, rdx
    mov rax, rcx
    mov r8, PROC_ENTRY_SIZE
    mul r8
    add rsi, rax
    mov rdx, [rsi + ProcessEntry.identity + ProcessIdentity.create_tick]
    ret

.not_found:
    mov rax, -1
    ret

utm_proc_verify_identity:
    call utm_proc_get_by_pid
    cmp rax, -1
    je .mismatch
    cmp rdx, rsi
    jne .mismatch
    xor rax, rax
    ret
.mismatch:
    mov rax, -1
    ret

utm_proc_fill_sample:
    mov rdi, rsi
    mov rcx, PROC_SAMPLE_SIZE / 8
    xor rax, rax
    rep stosq
    
    mov rdi, utm_proc_table
    mov rcx, rax
    xor rdx, rdx
    mov rax, rcx
    mov r8, PROC_ENTRY_SIZE
    mul r8
    add rdi, rax
    add rdi, ProcessEntry.identity
    mov rsi, rsi
    mov rcx, PROC_IDENTITY_SIZE / 8
    rep movsq
    
    ret

utm_spin_lock_acquire:
    mov rcx, utm_proc_table_lock
.lock_loop:
    mov rax, 1
    lock cmpxchg [rcx], rax
    jnz .lock_loop
    ret

utm_spin_lock_release:
    mov qword [utm_proc_table_lock], 0
    ret

%endif