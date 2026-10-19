# capability — Design

## Goals
1. **Security**: Fail-closed, least privilege, auditability.
2. **Reliability**: Deterministic behavior, no undefined states.
3. **Maintainability**: Clear separation of concerns, documented APIs.
4. **Performance**: O(1) common-path operations where possible.

## Non-Goals
- User-space execution (kernel-only subsystem).
- Network-facing APIs (exposed via IPC only).

## Data Structures
All mutable state resides in `.bss`, zero-initialized on load.
Configuration constants reside in `.data`.

## License
Apache-2.0
