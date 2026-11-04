# What Canvas Needs From the Kernel

For whoever works on `kernel/`. It lists what stands between Canvas and its
first frame on a real screen, smallest step first. Canvas's own older contract,
[`utkarsha-contract.md`](utkarsha-contract.md), describes numbered syscalls and
separate tasks, which the kernel does not have; this document follows the
model in [`docs/UBF_SPEC.md`](../../../docs/UBF_SPEC.md) and takes precedence.

## Where things stand

- Canvas builds, and all of it is tested on the development machine through a
  stand-in for these services (`tests/host/ut_host.asm`). It has never run on
  Utkarsha.
- `make ubf` produces `build/img/canvasd.ubf`, and `make ubf-check` loads it
  the way §9 of the spec says, offers only the exports in Step 1, and checks
  its first frame. Those exports are what stands between that test and a real
  screen.
- A program reaches the kernel by named UBF imports. Today the kernel exports
  `ut_console_print` and `ut_yield`, and `kernel/syscall` has no table, so the
  numbered syscalls in Canvas's `src/ut/*.asm` reach nothing.
- Every Canvas object is position independent (`make pic-check`), so it can be
  loaded at the program window.

## Step 1: first frame

Canvas already calls these names, so each export only needs to appear in
`kernel/exec/exports.asm` with this behaviour.

| Export | In | Out | Used for |
|---|---|---|---|
| `ut_mem_alloc` | `rdi` bytes, `rsi` flags | `rax` address or negative error, `r8` region handle | server arena, client regions, framebuffers, pixels |
| `ut_mem_free` | `rdi` region handle | `rax` 0 or negative error | client disconnect, buffers |
| `ut_time_now_ns` | | `rax` monotonic nanoseconds | frame timing, presentation |
| `ut_log_write` | `rdi` text, `rsi` length | `rax` 0 | startup and errors; `ut_console_print` takes a NUL-terminated string, so this could be a thin wrapper |
| `ut_fb_info` | `rdi` pointer to a 32-byte block | `rax` 0, or negative if there is no framebuffer | the block holds a `u64` virtual address, then `u32` width, height, pitch, format, then a `u64` size, from what `kernel/drivers/gpu/fb.asm` already keeps |
| `ut_yield` | | | exists |

`ut_fb_info` is new. In one address space, with `fb_init` having done the
mapping, asking the kernel for the result is simpler than mapping it again.
Pixels are 32-bit BGRX; Canvas does not read the format field yet, so a
framebuffer in another format would show wrong colours.

These six are the UBF's only required imports. It imports 33 more names, all
weak: the load succeeds without them, the slot stays 0, and Canvas's stub for
that name returns `-ENOSYS`. Canvas starts without any of them and yields in
its loop when `ut_waitset_create` is not there. An export for one of those
names therefore takes effect with no change to Canvas.

The first test program needs a way to be started: a UBF in the boot self-test
path, as `kernel/tests/ubf/hello.ubf` is, is enough.

`ubf_start` starts every program on a `FIBER_STACK_SIZE` (16 KiB) stack and does
not read the header's `stack_size`. The first frame uses about 520 bytes of it.
Nothing deeper has been measured; text, images and many clients will need more,
so honouring `stack_size` will matter before the login screen.

## Step 2: clients in other programs

- **KRN-03:** a channel a client can find. In one address space this can be as
  small as a published entry point that hands a program its `ChannelPair`
  (`client_accept` in `src/server/client/client.asm` already fills one).
- **KRN-04:** with one address space, buffer pixels are shared already; passing
  handles becomes passing checked numbers.
- `ut_waitset_create` and `ut_wait_wait`, or a way to sleep until a client has
  written, so that the event loop does not spin on `ut_yield`.

## Step 3: input

- Keyboard and mouse drivers, then `ut_input_register_callback` and
  `ut_input_unregister_callback`. Nothing can be typed on a login screen until
  this exists. Canvas already routes input it is given (`src/input/input.asm`);
  only the source is missing.

  | Export | In | Out |
  |---|---|---|
  | `ut_input_register_callback` | `rdi` function, `rsi` cookie | `rax` 0 or negative error |
  | `ut_input_unregister_callback` | | `rax` 0 |

  For each event the kernel calls the function with `rdi` a pointer to a
  24-byte record and `rsi` the cookie. Canvas copies the record before it
  returns and does not yield, so one call at a time from any fiber is enough.

  | Offset | Size | Field | Meaning |
  |---|---|---|---|
  | 0 | 4 | `type` | 1 key, 2 relative motion, 3 absolute position, 4 button, 5 scroll |
  | 4 | 4 | `code` | key: keycode 0–255; motion: dx; position: x; button: 0 left, 1 right, 2 middle; scroll: 0 vertical, 1 horizontal |
  | 8 | 4 | `value` | key, button: 1 down, 0 up; motion: dy; position: y; scroll: signed steps |
  | 12 | 4 | `device` | which device, for later per-device settings |
  | 16 | 8 | `time` | monotonic nanoseconds; 0 lets Canvas stamp it |

  Absolute positions are in framebuffer pixels. Keycodes are passed to clients
  as they are, so the drivers should agree on one numbering.
- Key repeat needs `ut_wait_wait` to honour its deadline (absolute monotonic
  nanoseconds): while a key is held the loop passes the time of the next
  repeat. Without waitsets the loop yields and repeats still come.
- `ut_timer_register` and `ut_timer_cancel`, for idle timeouts.

## Later

Only the native display backend, remote sharing and configuration need these:
`ut_mmio_map`, `ut_dma_alloc`, `ut_dma_free`, `ut_dma_sync`, `ut_irq_register`,
`ut_pci_*`, `ut_i2c_read`, `ut_i2c_write`, `ut_tls_*`, `ut_fs_*`, `ut_task_spawn`,
`ut_task_wait`, `ut_time_sleep_ns`, `ut_entropy_siphash_key`.

## What Canvas does on its side

- Keeps every object free of 32-bit absolute addresses (`make pic-check`).
- Produces one UBF from its objects with `tools/ubfpack.py`, since `utasm -f ubf`
  takes a single source.
- Reaches the kernel only through imports in that UBF; `make ubf-check` fails on
  a `syscall` instruction in the image. `src/ut/` remains only for the older
  ELF images.
