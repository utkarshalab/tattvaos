# tests/differential

Differential tests against Git for bridge output and reference implementations
for future hashing and chunking work.

`test_git_bridge.py` feeds assembly-produced first-parent fast-import history to
the system Git implementation, then independently verifies ancestry, exact
messages, quoted paths, file modes, and binary blob bytes.

`test_git_import.py` creates two commits with the system Git implementation,
exports full-tree snapshots, and feeds the untouched stream to the assembly
importer. It covers Git's feature/reset/from commands, plain and C-quoted paths,
multiline messages, and binary blob bytes.

`test_git_pack.py` asks the real smart bridge for a two-commit SHA-256 PACK,
loads it with Git's `index-pack`, and verifies every blob, tree, commit, and
first-parent edge through Git's object database.

`test_chunking.py` compares the scalar assembly content-defined chunker with an
independent implementation across fixed, seeded-random, and repetitive inputs.
It also verifies size limits, capacity errors, and output canaries.

The older assembly sketch is retained for now but is not part of the executable
gate.
