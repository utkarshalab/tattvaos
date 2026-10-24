# Calender model API (v1)

Native NASM calendar application core. The existing `calender/` directory spelling
is retained. Public symbols use `ucal_*`. Canvas can render the model later; this
model has no UI, host syscalls, allocator or global app state. Its native now
adapters call the checked shared `lib/time` service.

Build and test from the repository root:

```sh
make -C apps/calender test
make -C apps/clock test-api
```

Assembly interface: [symbol declarations](inc/api.inc), [NASM layouts](inc/calender.inc).
`build/calender-native.o` is a standalone relocatable object;
`build/libcalender.a` is the preferred archive for composition with other apps.
The `.so` is a host test artifact. Use the native x86-64 register calling convention documented below.
Archive linking extracts shared helpers only as needed, avoiding duplicate UTF-8
symbols when another app already supplies `lib/str` codecs.

## Contract

Dates use the proleptic Gregorian calendar, years 1..9999, months 1..12, days 1..31,
hours 0..23, minutes/seconds 0..59. There are no leap-second encodings. Epochs are
signed POSIX seconds. Fixed UTC offsets are signed seconds within -64800..64800
(18 hours), so half-hour/quarter-hour offsets are supported. A conversion applies
its supplied offset explicitly; there is no global timezone or implicit DST.
Weekday is Sunday=0..Saturday=6; yearday is zero-based. These two fields are derived
outputs, ignored when validating/converting an input date.

All structures use the fixed-width NASM layouts. Buffers
and contexts belong to the caller and must be valid for their complete declared
size. Callers serialize access to each mutable context. No pointer is retained.
Outputs are unchanged on failure. Date arithmetic supports identical input/output
pointers; other output buffers must not overlap inputs, stores or each other.
Zero-capacity event queries permit a null IDs pointer. Errors are negative:
`UCAL_INVALID=-1`, `UCAL_RANGE=-2`, `UCAL_FULL=-3`, `UCAL_NOT_FOUND=-4`, `UCAL_UNAVAILABLE=-5` for unavailable native time.

| Function | Result / behavior |
|---|---|
| `ucal_validate(date)` | 0 for a real date/time; checks month length/leap years |
| `ucal_to_epoch(date, offset, out)` | 0; UTC epoch = local civil time minus offset |
| `ucal_from_epoch(epoch, offset, out)` | 0; rejects a local result outside years 1..9999 |
| `ucal_month_grid(year, month, week_start, out)` | 0; 42 row-major cells, 0 outside current month |
| `ucal_add_days(date, delta, out)` | 0; signed days, time of day preserved |
| `ucal_add_months(date, delta, out)` | 0; signed months, clamp day to target month's last day |
| `ucal_iso_week(date, out[3])` | 0; ISO week-year, week 1..53, weekday Monday=1..Sunday=7 |

The grid includes its year, month, week start (Sunday=0), day count and first-cell
index. Canvas chooses labels, colors and navigation. A month change always
recalculates weekday/yearday. Invalid arithmetic and integer overflow leave the
output untouched. Epoch conversion checks the local date after applying the
offset; an extreme valid local date may map to a UTC instant just outside the
zero-offset civil range.

## Event store

Initialize each `ucal_store` with `ucal_store_init`. It holds 64 owned event records.
An event has a stable nonzero ID, inclusive UTC start, exclusive UTC end, flags,
and a nonempty NUL-terminated UTF-8 title (127 bytes maximum). Title controls and
malformed UTF-8 are rejected with `lib/str`'s checked decoder. Unused title bytes
are cleared. End must be after start; supported event bounds are UTC year 1
through the exclusive start of year 10000. Flag 1 denotes an all-day event and
requires both bounds to be UTC midnights; flag 0 is a timed event. Other flags
are rejected. Local all-day/DST policy belongs to a later timezone layer.

| Function | Behavior |
|---|---|
| `ucal_store_init(store)` | Reset the store and ID counter |
| `ucal_event_put(store, event, out_id)` | ID 0 creates; an existing ID replaces; 0 on success |
| `ucal_event_get(store, id, out)` | Copy the owned record; 0 on success |
| `ucal_event_delete(store, id)` | Erase and reclaim a slot; 0 on success |
| `ucal_event_query(store, from, to, ids, capacity, total)` | Return number written, with full match count in `total` |

Queries use interval overlap (`start < to && end > from`) and sort by start, then
ID. Capacity limits returned IDs without losing total count. IDs are monotonic
and not reused until store reset. Counter exhaustion fails instead of wrapping.
The bounded array uses a simple scan/sort; this is intentional for 64 records.

Events are in-memory model state. No automatic disk persistence, recurrence,
notifications, ICS import, alternate calendar or named timezone database is claimed.
A caller can export records through `get/query` and recreate them through `put`;
a durable versioned storage format can be added with the future app frontend.

## Validation

`make test` runs the actual NASM code against Python Gregorian references: 6000
random date/epoch/ISO/week arithmetic cases, 1500 month grids, exact range/leap
boundaries, pre-1970 timestamps, offset and alias checks, and full event-store
query/update/delete/UTF-8/error behavior. The native NASM integration test uses calendar + clock together, including
Nepal's +05:45 offset, preserved registers and callback stack alignment.
Date algorithms now live in `lib/cal/civil.asm`; app date symbols are thin
assembly delegates to that shared implementation. It reuses the corrected
`lib/cal/gregorian.asm` helpers. The app does not use the legacy library's
incompatible epoch structures. See the native wiring section below for live time.

## Assembly calling convention

Arguments use RDI, RSI, RDX, RCX, R8, R9 in the order shown in the API descriptions.
Pointers address caller-owned buffers; UTC/offset/delta values are signed where
specified. RAX returns status or count. RBX, RBP and R12..R15 are preserved;
other general registers may be clobbered. Align RSP to 16 bytes before CALL and
keep DF clear. There is no C header, C compiler or libc dependency.

From a repository-root include path:

```nasm
%include "apps/calender/inc/api.inc"
```

## Shared native library wiring

| API | Arguments | Behavior |
|---|---|---|
| `ucal_now` | RDI=UTC offset seconds, RSI=out date | Read real `lib/time` UTC and convert through `lib/cal` |
| `ucal_month_now` | RDI=offset, RSI=week start, RDX=out grid | Current local month through the same services |

Both return 0 on success, negative status on failure, leaving output unchanged.
The native archive/object now has a `time_read_realtime` dependency, resolved by
`lib/time/native.asm` in the kernel. It does not require a caller-supplied fake
clock. `ucal_now` reports -5 when that service is unavailable. Pure date/event
functions remain usable without hardware; archive linking pulls native adapters
only when referenced.

The kernel links these adapters and runs a small startup probe after calibrated
`time_init`. Canvas and storage are not involved. `make -C apps/clock test-wired`
executes the real app/shared-library code with only raw CMOS/TSC boundaries
substituted; this covers 800 conversions and RTC encodings/failure cases.
Production QEMU qualification is recorded with the shared time service.
