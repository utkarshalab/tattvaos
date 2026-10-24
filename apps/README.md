# apps — Applications Category

> User-facing applications built natively on Utkarsha OS.
> Each app runs directly on the unikernel with no OS abstraction layer.

---

The command shell lives in [`ush/`](ush/) — Utkarsha Shell.
[`calculator/`](calculator/) contains the scientific and programmer calculator.
[`calender/`](calender/) contains the calendar/date/event model API, and [`clock/`](clock/) contains clock/stopwatch/timer/alarm APIs for later Canvas frontends.
[`uedit/`](uedit/) contains the native terminal text editor, launched with `uedit FILE` from Ush.

---

## Philosophy

Applications in Utkarsha OS are not traditional executables.
They are compiled directly into the kernel image and run in ring 0.
There is no process isolation — isolation is provided by design and trust.
