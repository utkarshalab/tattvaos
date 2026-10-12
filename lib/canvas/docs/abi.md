# Canvas ABI Specification

**Calling conventions, data layouts, and binary interfaces for Canvas on Tattva OS x86-64.**

---

## 1. Tattva ABI (System Call Interface)

All Canvas ↔ Tattva kernel calls use this ABI.

### 1.1 Register Usage
| Register | Role | Preserved? |
|----------|------|------------|
| `rax` | Syscall number (in) / Return value (out) | No |
| `rdi` | Arg 1 | No |
| `rsi` | Arg 2 | No |
| `rdx` | Arg 3 | No |
| `rcx` | Arg 4 | No |
| `r8` | Arg 5 | No |
| `r9` | Arg 6 | No |
| `r10` | Arg 7 (if needed) | No |
| `r11` | Arg 8 (if needed) | No |
| `rbx` | Callee-saved | **Yes** |
| `rbp` | Callee-saved (frame pointer optional) | **Yes** |
| `r12-r15` | Callee-saved | **Yes** |
| `rsp` | Stack pointer (16-byte aligned at calls) | **Yes** |
| `xmm0-xmm15` | FP/Vector args & returns | No (volatile) |
| `ymm0-ymm15` / `zmm0-zmm31` | AVX/AVX-512 | No (volatile) |
| `rflags` | Status flags | No |

### 1.2 Stack Alignment
- **16-byte aligned** at every `call` instruction
- Shadow space: 32 bytes (4×8) reserved by caller for register spill
- Red zone: **Not used** (interrupt handlers may clobber)

### 1.3 Return Values
| Size | Registers |
|------|-----------|
| ≤ 64 bits | `rax` |
| 65–128 bits | `rax`, `rdx` |
| > 128 bits | Caller allocates buffer, passes pointer in `rdi` |

### 1.4 Error Returns
- Negative `rax` = `-Errno` (see `inc/errors.inc`)
- `rax == 0` = success (or positive handle/count)

---

## 2. Canvas Internal ABI (Module-to-Module)

Used for all `call` instructions within `canvasd` and client library.

### 2.1 Function Prologue / Epilogue (Macros in `inc/abi.inc`)

```nasm
%macro PROLOGUE 0
    push rbp
    mov  rbp, rsp
    ; Optional: sub rsp, N for locals (keep 16-byte aligned)
%endmacro

%macro EPILOGUE 0
    leave
    ret
%endmacro

%macro PROLOGUE_SAVE 1-*  ; registers to save (rbx, r12-r15)
    push rbp
    mov  rbp, rsp
    %rep %0
        push %1
        %rotate 1
    %endrep
%endmacro

%macro EPILOGUE_RESTORE 1-*
    %rep %0
        %rotate -1
        pop %1
    %endrep
    leave
    ret
%endmacro
```

### 2.2 Standard Calling Convention (Same as Tattva ABI)
- First 6 integer args: `rdi, rsi, rdx, rcx, r8, r9`
- Additional args: stack (right-to-left)
- FP/Vector args: `xmm0-xmm7` (also `ymm`/`zmm` if AVX)
- Return: `rax` / `rax+rdx` / hidden pointer

### 2.3 Special Conventions

#### 2.3.1 Arena Allocation Functions
```nasm
; All functions taking arena as first arg:
;   rdi = arena_ptr
;   rsi = size
;   rdx = alignment (power of 2, 0 = default 16)
; Returns: rax = pointer, or 0 on OOM (arena exhausted)
```

#### 2.3.2 Ring Buffer Operations
```nasm
; ring_push(ring, src, count)
;   rdi = ring_ptr, rsi = src_ptr, rdx = count
; Returns: rax = 0 OK, ENOSPC if full

; ring_pop(ring, dst, count)
;   rdi = ring_ptr, rsi = dst_ptr, rdx = count
; Returns: rax = actual_count (0 if empty)
```

#### 2.3.3 Handle Table Operations
```nasm
; handle_create(table, obj_ptr) -> handle
;   rdi = table_ptr, rsi = obj_ptr
; Returns: rax = handle (0 = fail)

; handle_resolve(table, handle) -> obj_ptr
;   rdi = table_ptr, rsi = handle
; Returns: rax = obj_ptr (0 = invalid generation)

; handle_destroy(table, handle)
;   rdi = table_ptr, rsi = handle
; Returns: rax = 0 OK
```

---

## 3. CWP Wire Protocol ABI

### 3.1 Message Header (On-Wire)
```nasm
struc MsgHdr
    .obj:     resd 1  ; u32: generation-tagged handle
    .opcode:  resw 1  ; u16: interface-specific opcode
    .flags:   resw 1  ; u16: NEED_ACK=1, HAS_HANDLES=2, IS_EVENT=4, TRANSACTION=8
    .len:     resd 1  ; u32: payload bytes (4-byte aligned)
endstruc
SIZEOF_MsgHdr equ 12
```

### 3.2 Handle Channel Message
```nasm
struc HandleMsg
    .count:   resd 1  ; u32: number of handles (max 16)
    .handles: resd 16 ; u32[16]: generation-tagged handles
endstruc
```

### 3.3 Channel Ring Layout
```
┌─────────────────────────────────────────────────────────────┐
│ Ring Header (64 bytes, cache-line aligned)                  │
│   u64 magic = 0x43414E564153434F ("CANVASCO")              │
│   u32 version = 1                                           │
│   u32 flags                                                 │
│   u64 head    (producer index)                              │
│   u64 tail    (consumer index)                              │
│   u32 cap     (power of 2, max messages)                    │
│   u32 msg_size (max message payload)                        │
│   u64 seq     (monotonic sequence for debugging)            │
│   u8  padding[24]                                           │
├─────────────────────────────────────────────────────────────┤
│ Message Slots (cap × (12 + msg_size), 4-byte aligned)       │
│   MsgHdr + payload...                                       │
└─────────────────────────────────────────────────────────────┘
```

### 3.4 Capability Bitmask (64-bit)
```nasm
; Core (always granted)
CAP_DISPLAY     equ 1 << 0
CAP_BUFFER      equ 1 << 1
CAP_SURFACE     equ 1 << 2
CAP_PRESENT     equ 1 << 3

; Output/Input
CAP_OUTPUT      equ 1 << 4
CAP_SEAT        equ 1 << 5
CAP_POINTER     equ 1 << 6
CAP_KEYBOARD    equ 1 << 7
CAP_TOUCH       equ 1 << 8
CAP_TABLET      equ 1 << 9

; Shell/Data
CAP_SHELL       equ 1 << 10
CAP_LAYER       equ 1 << 11
CAP_DECORATION  equ 1 << 12
CAP_DATA        equ 1 << 13

; Text/A11y
CAP_TEXT        equ 1 << 14
CAP_A11Y        equ 1 << 15

; Privileged (require trust profile + explicit grant)
CAP_CAPTURE     equ 1 << 32
CAP_INJECT      equ 1 << 33
CAP_POLICY      equ 1 << 34
CAP_DEBUG       equ 1 << 35
CAP_SESSION     equ 1 << 36
CAP_REMOTE      equ 1 << 37
```

---

## 4. Core Data Structure Layouts

### 4.1 Arena (16 bytes)
```nasm
struc Arena
    .base:    resq 1  ; u64: region base address
    .cursor:  resq 1  ; u64: current allocation pointer
    .limit:   resq 1  ; u64: region end (exclusive)
    .parent:  resq 1  ; u64: parent arena (0 = none)
endstruc
```

### 4.2 Region (Band List)
```nasm
struc Rect
    .x1: resd 1  ; i32: left (inclusive)
    .y1: resd 1  ; i32: top (inclusive)
    .x2: resd 1  ; i32: right (exclusive)
    .y2: resd 1  ; i32: bottom (exclusive)
endstruc
SIZEOF_Rect equ 16

struc Band
    .y1:    resd 1
    .y2:    resd 1
    .rects: resq 1  ; ptr to Rect array
    .count: resd 1
    .cap:   resd 1
endstruc

struc Region
    .bands:  resq 1  ; ptr to Band array
    .count:  resd 1
    .cap:    resd 1
    .arena:  resq 1  ; allocation arena
endstruc
```

### 4.3 Buffer Object
```nasm
struc Buffer
    .handle:        resd 1
    .generation:    resd 1
    .width:         resd 1
    .height:        resd 1
    .stride:        resd 1
    .format:        resd 1  ; DRM_FORMAT_*
    .modifier:      resq 1  ; DRM_FORMAT_MOD_*
    .base:          resq 1  ; cpu virtual address
    .dma_addr:      resq 1  ; device physical address
    .size:          resq 1  ; total bytes
    .acquire_fence: resd 1  ; fence handle
    .release_fence: resd 1  ; fence handle
    .timeline:      resd 1  ; timeline handle
    .acquire_point: resq 1  ; timeline point
    .release_point: resq 1  ; timeline point
    .state:         resb 1  ; FREE=0, ALLOCATED=1, ATTACHED=2, SCANOUT=3
    .refcount:      resd 1
    .client_id:     resd 1
endstruc
```

### 4.4 Surface State (Double-Buffered)
```nasm
struc SurfaceState
    .buffer:        resd 1
    .buf_x:         resd 1
    .buf_y:         resd 1
    .damage:        resq 1  ; Region*
    .opaque:        resq 1  ; Region*
    .input:         resq 1  ; Region*
    .transform:     resd 1  ; NORMAL=0, 90=1, 180=2, 270=3, FLIP_H=4, FLIP_V=8
    .scale:         resq 1  ; Fixed16_16 (1.0 = 0x10000)
    .subsurfaces:   resq 1  ; List head
    .frame_cbs:     resq 1  ; List head
    .pending:       resb 1
    .reserved:      resb 7
endstruc

struc Surface
    .current:   resb SIZEOF_SurfaceState
    .pending:   resb SIZEOF_SurfaceState
    .id:        resd 1
    .role:      resd 1  ; NONE=0, TOPLEVEL=1, POPUP=2, LAYER=3, SUBSURFACE=4
    .role_data: resq 1
    .output:    resd 1  ; primary output
    .z_order:   resq 1  ; rbtree node for z-order
    .client:    resq 1  ; Client*
endstruc
```

### 4.5 Client
```nasm
struc Client
    .id:            resd 1
    .trust_profile: resd 1  ; TRUST_*
    .caps:          resq 1  ; CapSet (u64)
    .arena:         resq 1  ; Arena*
    .obj_table:     resq 1  ; HandleTable*
    .tx_ring:       resq 1  ; Ring* (client→server)
    .rx_ring:       resq 1  ; Ring* (server→client)
    .handle_tx:     resq 1  ; Ring* (handles client→server)
    .handle_rx:     resq 1  ; Ring* (handles server→client)
    .quota:         resb SIZEOF_QuotaCounters
    .last_ping:     resq 1
    .state:         resb 1  ; CONNECTING=1, ACTIVE=2, THROTTLED=3, DEAD=4
    .pad:           resb 7
endstruc
```

### 4.6 Output
```nasm
struc Output
    .id:            resd 1
    .name:          resq 1  ; Str*
    .backend:       resq 1  ; Backend*
    .modes:         resq 1  ; List<Mode*>
    .current_mode:  resq 1
    .position:      resb SIZEOF_Point
    .scale:         resq 1  ; Fixed16_16
    .rotation:      resd 1
    .gamma_lut:     resq 1  ; u16[768] (256×3)
    .icc_profile:   resq 1  ; ICCProfile*
    .vrr_enabled:   resb 1
    .frame_clock:   resq 1  ; FrameClock*
    .damage:        resq 1  ; Region* (accumulated this frame)
endstruc
```

### 4.7 Event (24 bytes)
```nasm
struc Event
    .type:  resd 1  ; EV_*
    .time:  resq 1  ; u64 ns
    .a:     resd 1  ; context-dependent
    .b:     resd 1
    .c:     resd 1
endstruc
```

---

## 5. Client Library ABI (`canvas_client.o`)

### 5.1 Public Symbols (Exported)
```
canvas_connect        ; caps_wanted:u64 -> conn:u64 (0=fail)
canvas_disconnect     ; conn:u64
canvas_surface_create ; conn:u64 -> surface:u32
canvas_buffer_create  ; conn:u64, w:u32, h:u32, fmt:u32 -> buffer:u32
canvas_surface_attach ; surface:u32, buffer:u32, x:i32, y:i32
canvas_surface_damage ; surface:u32, x:i32, y:i32, w:u32, h:u32
canvas_surface_commit ; surface:u32, flags:u32
canvas_frame_request  ; surface:u32, cb_fn:u64, user_data:u64
canvas_toplevel_create ; surface:u32 -> toplevel:u32
canvas_toplevel_set_title ; toplevel:u32, str:u64, len:u32
canvas_toplevel_set_state ; toplevel:u32, state:u32 (MAXIMIZED=1, FULLSCREEN=2, MINIMIZED=4)
canvas_event_poll     ; conn:u64, event:Event* -> count:i32
canvas_clipboard_set  ; conn:u64, mime:Str*, data:u64, len:u32
canvas_clipboard_get  ; conn:u64, mime:Str* -> data:u64, len:u32
canvas_present_wait   ; conn:u64, surface:u32, timeout_ns:u64 -> PresentInfo*
```

### 5.2 Linking
- `canvas_client.o` is a **relocatable object** (not shared library)
- Linked into client image at build time
- No PLT/GOT — direct calls
- Uses same Tattva ABI

---

## 6. Build-Time Code Generation

### 6.1 `cwpgen` Output
For each `proto/*.cwp`:
- `inc/gen/cwp_*.inc` — Constants, structs, opcode enums
- `src/proto/gen/gen_*.asm` — Dispatch tables, encode/decode functions
- `src/client/gen/client_*.asm` — Client stubs (for `canvas_client.o`)

### 6.2 Generated Function Signatures
```nasm
; Server-side dispatcher (in gen_*.asm)
cwp_dispatch_<interface>:
    ; rdi = client, rsi = msg_hdr, rdx = payload_ptr, rcx = handle_array
    ; Returns: rax = 0 OK, negative error

; Client-side stub (in client_*.asm)
canvas_<interface>_<request>:
    ; Args per request, returns handle or error
```

---

## 7. SIMD Function ABI

### 7.1 CPU Feature Detection
```nasm
; cpuid.asm exports:
CPU_HAS_SSE2      equ 1 << 0
CPU_HAS_SSE3      equ 1 << 1
CPU_HAS_SSSE3     equ 1 << 2
CPU_HAS_SSE4_1    equ 1 << 3
CPU_HAS_SSE4_2    equ 1 << 4
CPU_HAS_AVX       equ 1 << 5
CPU_HAS_AVX2      equ 1 << 6
CPU_HAS_FMA       equ 1 << 7
CPU_HAS_AVX512F   equ 1 << 8
CPU_HAS_AVX512BW  equ 1 << 9
CPU_HAS_AVX512VL  equ 1 << 10
```

### 7.2 Dispatch Pattern
```nasm
; In blend.asm:
global blend_dispatch
blend_dispatch:
    mov rax, [cpu_features]
    test rax, CPU_HAS_AVX512F + CPU_HAS_AVX512BW + CPU_HAS_AVX512VL
    jnz .avx512
    test rax, CPU_HAS_AVX2
    jnz .avx2
    test rax, CPU_HAS_SSE2
    jnz .sse2
.scalar:
    jmp blend_scalar
.avx2:
    jmp blend_avx2
.avx512:
    jmp blend_avx512
```

### 7.3 Vector Function Signatures
```nasm
; All blend functions:
;   rdi = dst_ptr (u32*), rsi = src_ptr (u32*), rdx = width, rcx = height, r8 = stride
;   Returns: rax = 0
;   Assumes: width multiple of vector width (scalar handles remainder)

blend_scalar    ; 1 pixel/iter
blend_sse2      ; 4 pixels/iter (128-bit)
blend_avx2      ; 8 pixels/iter (256-bit)
blend_avx512    ; 16 pixels/iter (512-bit)
```

---

## 8. Tattva Service Binding ABI (`src/tattva/*.asm`)

Each `tv_*.asm` exports thin wrappers matching the contract in `tattva-contract.md`.

### 8.1 Naming Convention
```nasm
; tv_mem.asm
global tv_mem_alloc, tv_mem_free, tv_mem_resize, tv_mem_map_phys, tv_mem_info

; tv_time.asm
global tv_time_now_ns, tv_time_now_us, tv_time_now_ms, tv_time_tsc
global tv_time_sleep_until, tv_time_sleep_ns, tv_timer_register, tv_timer_cancel

; ... etc for all services
```

### 8.2 Stub Implementation (C0)
```nasm
; C0: All return ENOSYS (-15) until Tattva implements
tv_mem_alloc:
    mov rax, -15  ; ENOSYS
    ret
```

---

## 9. Memory Layout Conventions

### 9.1 Kernel/Canvas Split (Tattva Defines)
```
0x0000_0000_0000_0000 - 0x0000_7FFF_FFFF_FFFF  User/Canvas space (128 TB)
0xFFFF_8000_0000_0000 - 0xFFFF_FFFF_FFFF_FFFF  Kernel space
```

### 9.2 Canvas Internal Layout (Example)
```
0x0000_0000_0000_0000 - 0x0000_0000_00FF_FFFF  Canvas code + RO data (~16 MB)
0x0000_0000_0100_0000 - 0x0000_0000_01FF_FFFF  Global arena (~16 MB)
0x0000_0000_0200_0000 - 0x0000_0000_0FFF_FFFF  Per-client arenas (dynamic)
0x0000_0000_1000_0000 - 0x0000_0000_FFFF_FFFF  DMA/Scanout buffers (mapped on demand)
0x0000_0001_0000_0000 - 0x0000_00FF_FFFF_FFFF  Shared rings, handle tables
0x0000_0100_0000_0000 - 0x0000_7FFF_FFFF_FFFF  Client code (loaded by Tattva)
```

### 9.3 Alignment Requirements
| Type | Alignment |
|------|-----------|
| Arena base | 4 KB (page) |
| Ring buffer | 64 B (cache line) |
| DMA buffer | 4 KB (page), prefer 2 MB (huge page) |
| Stack | 16 B |
| SIMD loads/stores | 16 B (SSE), 32 B (AVX), 64 B (AVX-512) |

---

## 10. Versioning

| ABI Version | Canvas Phases | Notes |
|-------------|---------------|-------|
| 1.0 | C0–C33 | Initial stable ABI |
| 2.0 | Post-v1 | If HW domains added |

**ABI Stability Promise**: Within v1.x, no breaking changes to:
- Tattva syscall numbers/structures
- CWP wire format (only additive interfaces)
- Client library public symbols
- Core data structure layouts (only append fields)

Breaking changes → major version + new `canvas_client.o` + protocol version bump.