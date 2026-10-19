# security/usrauth/subject — Subject Table & Transitions

## Purpose
Subject identity model: subject table, handle-based references, and subject
state transitions. Everything in usrauth consumes subject handles.

## Architecture
- **Table** — subject registry (subject_id -> subject record)
- **Handle** — unforgeable subject reference (opaque handle)
- **Transition** — subject state machine transitions (active, suspended, revoked)

## API (skeleton)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `subject_init` | none | rax = 0 | Initialize subject table |
| `subject_shutdown` | none | rax = 0 | Shut down |
| `subject_status` | none | rax = status | Current status |
| `subject_create` | credentials | rax = subject_id | Create a new subject |
| `subject_lookup` | handle | rax = subject record | Look up subject by handle |
| `subject_transition` | subject, new_state | rax = result | Transition subject state |

## Design Decisions
- Subjects are referenced by opaque handles (never raw pointers).
- Subject records are immutable once created; state changes via transitions only.
- Subject deletion is logical (revoked), not physical, to preserve audit references.

## Status
Skeleton. `table.asm` / `transition.asm` export `subject_init`, `subject_shutdown`, `subject_status` as no-op stubs.

## Tests
Run: `make -C security/usrauth/subject test`

## License
Apache-2.0
