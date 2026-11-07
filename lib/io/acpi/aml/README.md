# lib/io/acpi/aml — the AML interpreter

Runs the ACPI bytecode in the DSDT and SSDTs: builds the namespace, calls
methods, reads and writes fields. Plan and status:
[../ROADMAP.md](../ROADMAP.md) (§4.2 and Phase 1).

## Use

```
aml_init(memory, size)              ; memory for nodes and values
aml_load(dsdt)                      ; then each SSDT
aml_eval_path("\_SB.PCI0._STA", args, count, &result)
aml_find("\_SB.PCI0")               ; the node, or 0
aml_run_reg(space)                  ; a handler for a space exists: _REG
aml_initialize()                    ; \_SB._INI, then _STA and _INI
aml_find_device("PNP0C50", n)       ; the nth present device with that ID
aml_match_id(node, "PNP0C50")       ; its _HID or _CID
aml_device_status(node)             ; the _STA bits found
aml_get_crs(node, &buffer)          ; its _CRS resource template
aml_res_next(buf, len, &off, &res)  ; the next descriptor, decoded
```

All entry points return 0 or a negative `AML_E*` error (`aml.inc`). One
caller at a time. A result lives in temporary memory until the next call
into the interpreter; copy what must be kept.

The outside world comes in through hooks, all optional:

| Hook | Called for |
|---|---|
| `aml_region_fn` | Every field access unit: space, address, width, read or write. The sandbox belongs here. Without it, field access fails with `AML_EUNSUPPORTED` |
| `aml_notify_fn` | `Notify (object, value)` |
| `aml_sleep_fn` | `Sleep` and `Stall`, in nanoseconds |
| `aml_clock_fn` | `Timer` |
| `aml_debug_fn` | Stores to `Debug` |

## Files

| File | What it does |
|---|---|
| `aml.inc` | Values, nodes, frames, errors, limits |
| `heap.asm` | One region: permanent memory from the bottom, temporary from the top |
| `ns.asm` | Namespace nodes, lookup rules, predefined names |
| `value.asm` | Copies, conversions, comparison |
| `parse.asm` | Bounded reads: bytes, package lengths, name strings |
| `exec.asm` | Statements, named-object operators, method calls, targets, Store |
| `ops.asm` | Expressions |
| `field.asm` | Region fields (plain, index, bank) and buffer fields |
| `api.asm` | `aml_init`, `aml_load`, `aml_find`, `aml_eval_path`, `\_OSI` |
| `init.asm` | `_REG`, the `_STA`/`_INI` walk, device IDs and lookup |
| `res.asm` | `_CRS` and resource descriptors, decoded into a 56-byte record |

## Safety

Every read is checked against the end of the term list it belongs to.
Method calls are limited to 32 deep, `While` to a million iterations per
evaluation, and machine stack use to 10 KB. Running out of memory fails
cleanly. Names a method creates disappear when it returns.

## Tests

```
sh lib/io/acpi/aml/tests/run_tests.sh
```

`aml_gen.py` builds test tables term by term. The three suites:

| Suite | Checks | Covers |
|---|---|---|
| `test_aml.py` | 119 | The interpreter, every truncation of a table, 3 000 mutated tables |
| `test_init.py` | 30 | The start-up walk, device IDs, `_REG` |
| `test_res.py` | 48 | Every resource descriptor, malformed ones, 5 000 random templates, `_CRS` |
