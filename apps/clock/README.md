# Clock model API (v1)

Native NASM clock application core, ready for a later Canvas frontend. It supplies
clock sampling, stopwatches, countdown timers and UTC alarms. Models and buffers
belong to the caller. There is no UI, sleeping loop, OS syscall, heap, static app
state or hardwired RTC access.

```sh
make -C apps/clock test
```

Assembly interface: [symbol declarations](inc/api.inc), [NASM layouts](inc/clock.inc).
Build outputs are `build/clock-native.o` and `build/libclock.a`. Use the archive
when linking a future application, and SysV AMD64 for calls/callbacks. The `.so`
and API-test executable are host validation artifacts. Native adapters resolve
shared `lib/time`/`lib/cal` services supplied by the kernel.

## Common contract

All contexts must be initialized before use, fully accessible and serialized by
the caller. Callbacks must preserve SysV callee-saved registers and write their
outputs before returning 0. Other statuses mean unavailable. Pointers are never
retained except function pointers in the caller-owned source table. Output buffers
must not overlap contexts or other inputs. Failed calls do not partially update
outputs/state. Error codes: invalid argument -1, range/regression/overflow -2,
invalid state or unavailable source -3, capacity full -4, ID not found -5.

Monotonic samples and durations are unsigned 64-bit nanoseconds. Use the same
monotonic clock domain for a context's entire lifetime. Reads/mutations reject
backward samples; reset explicitly starts a new lifetime. Monotonic wrap is a
regression error, not a guessed elapsed interval. UTC alarms use signed POSIX
seconds within UTC years 1..9999. Leap seconds are not separately encoded.

## Clock sampling and world clocks

`uclock_read(sources, out_sample)` calls two supplied functions:

- `monotonic(uint64_t *out_ns) -> 0/status`
- `realtime(uclock_wall_time *out) -> 0/status`

On success the sample contains monotonic nanoseconds, UTC seconds and nanoseconds
0..999999999. Callbacks run sequentially, so this is not an atomic calibration
pair. Missing/failed callbacks return unavailable; malformed wall time returns a
range error and leaves the caller's sample unchanged. A backend should return
unavailable until its clock is ready rather than manufacture an epoch.

For world clocks, pass sampled UTC seconds and each explicit fixed offset to
[`ucal_from_epoch`](../calender/README.md). Formatting, 12/24-hour display, names and
named timezone/DST rules belong to the presentation/timezone layer. The built-in native source table is already wired to `lib/time`; callers can
use `uclock_read_native` directly.

## Stopwatch

Initialize/reset with `uclock_stopwatch_init`. States are IDLE=0, RUNNING=1,
PAUSED=2. `uclock_stopwatch_start(watch, now)` starts or resumes; starting while
running returns a state error. `pause(watch, now)` freezes elapsed time.
`read(watch, now, out_elapsed)` returns accumulated nanoseconds including the
current running segment. `lap(watch, now, out_elapsed)` stores one cumulative lap
while running, up to 32. The count and lap values are caller-readable fields.
Read/pause/lap guard against overflow and backward monotonic timestamps. Reset
clears laps and elapsed time; pausing retains both. Successful calls return 0.

## Countdown

Initialize/cancel/reset with `uclock_countdown_init`. Start/rearm with
`uclock_countdown_start(timer, duration_ns, now_ns)`; zero duration is rejected.
Rearming replaces the old timer and establishes a new timestamp baseline.
`uclock_countdown_poll(timer, now, out_remaining)` returns **1 exactly when the
running timer becomes EXPIRED=3**, otherwise 0. Remaining time saturates at zero;
further polls cannot repeatedly deliver expiry. Pause consumes elapsed time first;
if it expires during that call, pause returns 1 and leaves the timer expired.
Resume accepts only PAUSED and excludes time spent paused. Relative arithmetic
avoids overflow from forming an absolute deadline.

`uclock_duration_parts(ns, out[4])` produces total hours, minutes 0..59, seconds
0..59 and nanoseconds. Total hours are not reduced modulo 24. Canvas formats these
numeric values however it needs.

## Alarms

Initialize `uclock_alarms` with `uclock_alarms_init`. It contains 32 records. Use
`uclock_alarm_put(store, alarm, out_id)` to create (ID=0) or update an existing ID.
A record contains ID, UTC due time, repeat period in seconds (0 means one-shot),
and enabled (0/1). Period is bounded by the supported civil date span. IDs never
wrap or reuse until reset. `get` copies a record; `delete` erases and reclaims it.
Disabled/fired records retain their slots and IDs until explicitly deleted.

`uclock_alarm_poll(store, now_utc, notifications, capacity)` returns the number of
notifications written, ordered by due time then ID. Capacity 0 is a no-op and
permits a null notification buffer. Unemitted due alarms are not consumed. A
notification contains ID, original scheduled time, observed time and count of
additional missed periods. A repeating alarm coalesces all due occurrences into
one notification and advances directly to its first future due time. One-shots
are disabled after emission. Repeats that would leave the supported civil range
are disabled after their final notification instead of wrapping.

Forward wall-clock jumps may coalesce missed repeats; backward jumps do not
re-deliver occurrences already consumed. Re-enabling/updating an alarm explicitly
changes that schedule. Periods are elapsed UTC seconds, so 86400 is not a named-
timezone civil-day recurrence across DST. Alarm polling neither sleeps nor calls
UI code: Canvas can consume notifications on its own loop, avoiding reentrancy.
Polling frequency determines delivery latency. No wake-from-suspend, audio,
background scheduler registration or persistence is claimed by this API.

## Validation

The actual native API passes deterministic fake-clock tests, 5000 modeled
stopwatch operations, 2000 countdown cases and 1000 randomized alarm queue polls.
Tests cover pause/resume, laps, exact and repeated expiry, overflow, regression,
malformed/unavailable sampling, capacity/backpressure, coalescing, ordering,
backward wall jumps and date-range exhaustion. `tests/test_api.asm` includes the public NASM declarations and uses both
archives together, checking preserved registers and callback stack alignment.
The native wiring test additionally exercises the real shared time/calendar
implementations with fake raw hardware boundaries. Production QEMU qualification
is recorded with the shared time service; physical hardware is not qualified.

## Assembly calling convention

Arguments use RDI, RSI, RDX, RCX, R8, R9 in the order shown in the API descriptions.
Pointers address caller-owned buffers; UTC/offset/delta values are signed where
specified. RAX returns status or count. RBX, RBP and R12..R15 are preserved;
other general registers may be clobbered. Align RSP to 16 bytes before CALL and
keep DF clear. There is no C header, C compiler or libc dependency.

From a repository-root include path:

```nasm
%include "apps/clock/inc/api.inc"
```

## Built-in native services

- `uclock_read_native(RDI=out sample)` uses `uclock_native_sources`, already bound
  to `time_read_monotonic` and `time_read_realtime` from `lib/time/native.asm`.
- `uclock_local_now(RDI=offset seconds, RSI=out civil date)` reads checked UTC from
  `lib/time` and converts it with `cal_civil_from_epoch` from `lib/cal/civil.asm`.
  The output uses the same 64-byte date layout as the calendar app.
- `uclock_native_sources` can also be passed explicitly to `uclock_read`.

No source callbacks need to be constructed for normal native use. The injectable
sampling API remains available for deterministic tests and alternate backends.
The kernel links the native sampling/local-time adapters and runs them during its
startup probe, after `time_init` successfully calibrates TSC and starts monotonic
tracking. Timer/stopwatch updates and alarm polling retain their explicit time
arguments; use the native sample's monotonic/UTC values respectively.

Standalone native objects intentionally retain references to the shared kernel
services; the archive is preferred for composition. The library does not silently
initialize/calibrate global hardware clocks from an app call. Uninitialized time
or invalid/unstable CMOS produces an unavailable error and leaves output intact.
`make -C apps/clock test-wired` runs actual `lib/time` monotonic/RTC and `lib/cal`
conversion logic, substituting only raw TSC/CMOS reads. No C code is introduced.
