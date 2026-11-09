# Definition of Done

What has to be true before a ROADMAP item is marked ✓, and what each
subsystem adds to that. Decision 0015 says how Canvas is tested; this says
when testing is enough.

## Every item

1. **It works through the way clients and the kernel reach it.** That means
   a protocol request, an input record or a kernel import, not only a direct
   call.
2. **Tests.** A host suite case covers each behaviour the item names, the
   refusals as well as the successes (wrong capability, bad handle, out of
   range).
3. **Mutation checked.** Each behaviour's key logic, removed or changed once,
   makes a test fail. Logic that no test can catch is either redundant (and
   removed) or untested (and the item stays ◐).
4. **The checks pass.** `make check` passes: debug and release, field widths,
   W^X, position independence, symbol consistency, every host suite, the
   decoders, the fuzzers, the UBF.
5. **Docs.**
   - The ROADMAP row says what exists, where, and what is left. A row that
     still lists what is left stays ◐.
   - The protocol files describe every new request and event.
   - `KERNEL_NEEDS.md` and `utkarsha-contract.md` describe anything new
     asked of the kernel.
   - A decision record covers any choice between real alternatives.
6. **Committed** one file per commit with a message saying what changed and
   why, and pushed.
7. **A bug fixed** comes with the test that fails without the fix, and a row
   in `regressions.md` (QA-19).

## By subsystem

| Subsystem | Areas | Also required |
|---|---|---|
| Parsers and decoders | MED, TXT (fonts), COL (ICC), DAT, KEY (keymaps) | A fuzz target in `make check`; for an image format, the reference comparison in `compare_images.py` (exact for lossless, the PSNR floor for lossy); a format not supported is refused, never decoded wrongly |
| Protocol | PRO, SUR, DAT | The request in `proto/*.cwp` and dispatch generated; each request refused cleanly when short, without its capability, or naming another client's object; reached by `test_fuzz` |
| Compositor and rendering | CMP, G2D, OUT | A pixel check (or golden frame) for what is drawn, on a scaled output too when scale matters; damage covers what changed and no less |
| Input | KEY, PTR, TCH, IME | Delivery to the right surface, behind the right capability; what happens when the surface goes away mid-way |
| Shell and windows | WIN, DSK | Placement and focus checked; the item works on more than one output and workspace if it can reach them |
| Sessions, security, governance | SES, SEC, GOV | The refusal paths tested as carefully as the success; the lock screen cannot be got round by the feature |
| Performance claims | PRF, and any item with a target | A benchmark in `tests/bench` recording the number on reference hardware (none yet: such items stay ◐) |
| Kernel-facing | KRN, and items needing a new `ut_*` export | Works with the export missing (a weak import returning `-ENOSYS`), and the shim models the export's documented layout |

## Invariants checked everywhere

- Stack aligned to 16 bytes at every call (`PROLOGUE_SAVE` arithmetic in each
  function's comment).
- No access wider than its field (`field-width-check`).
- No 32-bit absolute address (`pic-check`); no writable and executable segment
  (`wx-check`).
- One definition per global, none missing; no unused `extern`
  (`symbol-check`).
- Every allocation bounded and every handle checked through `handle_resolve`
  (REL-01 and SEC-06 audit the rest).
