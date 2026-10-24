# lib/cal — Calendar Library

> Calendar and date utilities for Utkarsha OS.

Implements: Gregorian calendar, Unix timestamp conversion,
date arithmetic, ISO 8601 formatting.

Part of the `lib/` category in Utkarsha OS.

## Checked native civil API

`civil.asm` / `civil_api.inc` provide checked Gregorian conversions, month grids,
date arithmetic and ISO week dates for years 1..9999, signed POSIX epochs and
explicit fixed UTC offsets. `civil.inc` defines the 64-byte date and month-view
layouts. Calendar app date symbols delegate to these shared functions; the clock
native local-time adapter uses the same converter. The API reuses Gregorian
helpers and does not depend on app code. See `apps/calender/README.md` for the
matching register contracts and semantics. The older `unix.asm`/`iso8601.asm`
interfaces are not used by this checked path.
