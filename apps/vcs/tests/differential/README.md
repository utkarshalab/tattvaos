# tests/differential

Differential tests against Git for bridge output and reference implementations
for future hashing and chunking work.

`test_git_bridge.py` feeds assembly-produced first-parent fast-import history to
the system Git implementation, then independently verifies ancestry, exact
messages, quoted paths, file modes, and binary blob bytes.

The older assembly sketch is retained for now but is not part of the executable
gate. Hashing and chunking differential suites remain pending.
