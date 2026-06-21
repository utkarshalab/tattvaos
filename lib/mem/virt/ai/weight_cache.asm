; =============================================================================
; Tattva OS — lib/mem/virt/weight_cache.asm
; =============================================================================
; Weight Cache Manager — Subfeature 36.2.
;
; Manages model weight buffers in RAM. Active models are pinned (never evicted
; to swap), while inactive models are subject to Least-Recently-Used (LRU)
; eviction when the total cache capacity limit is exceeded.
;
; Tracks up to 16 models resident in the cache simultaneously.
;
; API:
;   weight_cache_init(max_bytes)        — Initialise weight cache bounds.
;   weight_cache_pin(ptr, size, id)     — Load and pin weights; evict LRU if full.
;   weight_cache_unpin(id)              — Unpin model weights (allows eviction).
;   weight_cache_evict_lru()            — Evict one inactive LRU model.
;   weight_cache_access(id)             — Update model's LRU timestamp.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_WEIGHT_CACHE_ASM
%define LIB_MEM_VIRT_WEIGHT_CACHE_ASM

[BITS 64]

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
WEIGHT_MAX_MODELS       equ 16

; Model Entry Layout: 40 bytes
MODEL_ENTRY_ID          equ 0       ; dq: model ID (0 if free slot)
MODEL_ENTRY_PTR         equ 8       ; dq: weights memory pointer
MODEL_ENTRY_SIZE        equ 16      ; dq: weight size in bytes
MODEL_ENTRY_PINNED      equ 24      ; dq: 1 if pinned, 0 if inactive/evictable
MODEL_ENTRY_ACC_TICK    equ 32      ; dq: virtual timestamp tick of last access

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; weight_cache_init — Initialize cache max size and zero the entry table
; Input:  RDI = Max cache bytes limit
; Output: RAX = 1
; Clobbers: RAX, RCX, RDI
; ---------------------------------------------------------------------------
global weight_cache_init
weight_cache_init:
    push rdi
    push rcx

    mov  [sys_weight_cache_max_bytes], rdi
    mov  qword [sys_weight_cache_total_bytes], 0
    mov  qword [sys_weight_cache_pinned_bytes], 0
    mov  qword [sys_weight_cache_resident_models], 0
    mov  qword [sys_weight_cache_tick], 0

    ; Zeros the models entry table: 16 entries * 40 bytes = 640 bytes
    lea  rdi, [sys_weight_models_table]
    xor  rax, rax
    mov  rcx, 80                    ; 80 qwords = 640 bytes
    rep  stosq

    mov  rax, 1
    pop  rcx
    pop  rdi
    ret

; ---------------------------------------------------------------------------
; weight_cache_pin — Load/Mark model weights as active (pinned in RAM)
; Input:
;   RDI = Weight Buffer Pointer (simulated RAM location)
;   RSI = Weight Buffer Size (bytes)
;   RDX = Model ID (non-zero)
; Output: RAX = 1 on success, 0 on failure (no space, even after eviction)
; Clobbers: RAX, RBX, RCX, RDI, RSI, RDX, R8, R9, R10
; ---------------------------------------------------------------------------
global weight_cache_pin
weight_cache_pin:
    test rdx, rdx
    jz   .fail
    test rsi, rsi
    jz   .fail
    test rdi, rdi
    jz   .fail

    ; Check if model is already registered
    push rdi
    push rsi
    push rdx
    
    mov  r8, rdx                    ; R8 = target model_id
    xor  rcx, rcx                   ; RCX = index loop
.find_existing:
    lea  rax, [sys_weight_models_table + rcx * 40]
    cmp  [rax + MODEL_ENTRY_ID], r8
    je   .handle_existing
    inc  rcx
    cmp  rcx, WEIGHT_MAX_MODELS
    jb   .find_existing
    jmp  .not_existing

.handle_existing:
    ; Model already exists: update state
    ; If was unpinned, adjust totals
    mov  rsi, [rax + MODEL_ENTRY_SIZE]
    cmp  qword [rax + MODEL_ENTRY_PINNED], 1
    je   .existing_done
    
    ; Transition from unpinned to pinned
    mov  qword [rax + MODEL_ENTRY_PINNED], 1
    add  [sys_weight_cache_pinned_bytes], rsi
.existing_done:
    ; Update access tick
    inc  qword [sys_weight_cache_tick]
    mov  r10, [sys_weight_cache_tick]
    mov  [rax + MODEL_ENTRY_ACC_TICK], r10

    pop  rdx
    pop  rsi
    pop  rdi
    mov  rax, 1
    ret

.not_existing:
    pop  rdx
    pop  rsi
    pop  rdi

    ; RDX = model ID, RSI = size, RDI = ptr
    ; Check if individual model size exceeds maximum capacity of cache
    mov  r8, [sys_weight_cache_max_bytes]
    cmp  rsi, r8
    ja   .fail

.eviction_loop:
    ; Check if adding this model exceeds cache size: total_bytes + size <= max_bytes
    mov  rax, [sys_weight_cache_total_bytes]
    add  rax, rsi
    cmp  rax, r8
    jbe  .allocate_slot             ; fits without eviction!

    ; Evict one model using LRU
    push rdi
    push rsi
    push rdx
    call weight_cache_evict_lru
    pop  rdx
    pop  rsi
    pop  rdi
    test rax, rax
    jz   .fail                      ; nothing to evict, but cache is full!
    jmp  .eviction_loop             ; recheck capacity

.allocate_slot:
    ; Find a free slot in models table
    xor  rcx, rcx
.find_free_slot:
    lea  rax, [sys_weight_models_table + rcx * 40]
    cmp  qword [rax + MODEL_ENTRY_ID], 0
    je   .slot_found
    inc  rcx
    cmp  rcx, WEIGHT_MAX_MODELS
    jb   .find_free_slot
    jmp  .fail                      ; table full (too many models resident)

.slot_found:
    ; Fill slot
    mov  [rax + MODEL_ENTRY_ID], rdx
    mov  [rax + MODEL_ENTRY_PTR], rdi
    mov  [rax + MODEL_ENTRY_SIZE], rsi
    mov  qword [rax + MODEL_ENTRY_PINNED], 1
    
    inc  qword [sys_weight_cache_tick]
    mov  r9, [sys_weight_cache_tick]
    mov  [rax + MODEL_ENTRY_ACC_TICK], r9

    ; Update totals
    add  [sys_weight_cache_total_bytes], rsi
    add  [sys_weight_cache_pinned_bytes], rsi
    inc  qword [sys_weight_cache_resident_models]

    mov  rax, 1
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; weight_cache_unpin — Mark model weights as unpinned (inactive / evictable)
; Input:  RDI = Model ID
; Output: RAX = 1 on success, 0 if model not found
; Clobbers: RAX, RCX
; ---------------------------------------------------------------------------
global weight_cache_unpin
weight_cache_unpin:
    test rdi, rdi
    jz   .fail

    xor  rcx, rcx
.find_loop:
    lea  rax, [sys_weight_models_table + rcx * 40]
    cmp  [rax + MODEL_ENTRY_ID], rdi
    je   .unpin_it
    inc  rcx
    cmp  rcx, WEIGHT_MAX_MODELS
    jb   .find_loop
    jmp  .fail

.unpin_it:
    cmp  qword [rax + MODEL_ENTRY_PINNED], 0
    je   .already_unpinned          ; idempotent

    mov  qword [rax + MODEL_ENTRY_PINNED], 0
    mov  rsi, [rax + MODEL_ENTRY_SIZE]
    sub  [sys_weight_cache_pinned_bytes], rsi

.already_unpinned:
    mov  rax, 1
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; weight_cache_evict_lru — Evict Least Recently Used unpinned model weights
; Output: RAX = Evicted model ID, 0 if nothing evictable
; Clobbers: RAX, RCX, RDX, R8, R9, R10
; ---------------------------------------------------------------------------
global weight_cache_evict_lru
weight_cache_evict_lru:
    xor  rcx, rcx
    xor  r8, r8                     ; R8 = pointer to best victim entry
    mov  r9, 0xFFFFFFFFFFFFFFFF     ; R9 = lowest access tick found

.lru_search:
    lea  rax, [sys_weight_models_table + rcx * 40]
    mov  rdx, [rax + MODEL_ENTRY_ID]
    test rdx, rdx
    jz   .next_entry                ; slot is empty
    
    ; Must be unpinned to be eligible for eviction
    cmp  qword [rax + MODEL_ENTRY_PINNED], 0
    jne  .next_entry

    mov  r10, [rax + MODEL_ENTRY_ACC_TICK]
    cmp  r10, R9
    jae  .next_entry
    
    mov  r9, r10                    ; update lowest tick
    mov  r8, rax                    ; update candidate pointer
.next_entry:
    inc  rcx
    cmp  rcx, WEIGHT_MAX_MODELS
    jb   .lru_search

    ; If we found a victim, evict it
    test r8, r8
    jz   .no_victim

    ; Subtract size from totals
    mov  rax, [r8 + MODEL_ENTRY_ID] ; RAX = evicted model ID
    mov  rsi, [r8 + MODEL_ENTRY_SIZE]
    sub  [sys_weight_cache_total_bytes], rsi
    dec  qword [sys_weight_cache_resident_models]

    ; Zero out the entry slot
    mov  qword [r8 + MODEL_ENTRY_ID], 0
    mov  qword [r8 + MODEL_ENTRY_PTR], 0
    mov  qword [r8 + MODEL_ENTRY_SIZE], 0
    mov  qword [r8 + MODEL_ENTRY_PINNED], 0
    mov  qword [r8 + MODEL_ENTRY_ACC_TICK], 0
    ret

.no_victim:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; weight_cache_access — Touch model to update its LRU status
; Input:  RDI = Model ID
; Output: RAX = 1 if updated, 0 if not resident
; Clobbers: RAX, RCX, RDX
; ---------------------------------------------------------------------------
global weight_cache_access
weight_cache_access:
    test rdi, rdi
    jz   .fail

    xor  rcx, rcx
.find_entry:
    lea  rax, [sys_weight_models_table + rcx * 40]
    cmp  [rax + MODEL_ENTRY_ID], rdi
    je   .touch_it
    inc  rcx
    cmp  rcx, WEIGHT_MAX_MODELS
    jb   .find_entry
    jmp  .fail

.touch_it:
    inc  qword [sys_weight_cache_tick]
    mov  rdx, [sys_weight_cache_tick]
    mov  [rax + MODEL_ENTRY_ACC_TICK], rdx
    mov  rax, 1
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_weight_cache_max_bytes
sys_weight_cache_max_bytes:     dq 0

align 8
global sys_weight_cache_total_bytes
sys_weight_cache_total_bytes:   dq 0

align 8
global sys_weight_cache_pinned_bytes
sys_weight_cache_pinned_bytes:  dq 0

align 8
global sys_weight_cache_resident_models
sys_weight_cache_resident_models: dq 0

align 8
sys_weight_cache_tick:          dq 0

; ---------------------------------------------------------------------------
; BSS — entry array for active resident models (16 models)
; ---------------------------------------------------------------------------
section .bss

align 64
sys_weight_models_table:        resb (WEIGHT_MAX_MODELS * 40)

section .text

%endif ; LIB_MEM_VIRT_WEIGHT_CACHE_ASM
