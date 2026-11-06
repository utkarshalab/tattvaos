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
```

All entry points return 0 or a negative `AML_E*` error (`aml.inc`). One
caller at a time. A result lives in temporary memory until the next
`aml_load` or `aml_eval_path`.

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

## Safety

Every read is checked against the end of the term list it belongs to.
Method calls are limited to 32 deep, `While` to a million iterations per
evaluation, and machine stack use to 10 KB. Running out of memory fails
cleanly. Names a method creates disappear when it returns.

## Tests

```
sh lib/io/acpi/aml/tests/run_tests.sh
```

`aml_gen.py` builds test tables term by term, and `test_aml.py` runs 118
checks against them. The checks cover every truncation of a table and
3 000 randomly mutated tables.
