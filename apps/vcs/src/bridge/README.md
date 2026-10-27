# src/bridge

Git bridge: fast-import export plus packet-line framing for future smart
protocol negotiation.

`bridge_git_export` emits one validated VCS snapshot as a real Git fast-import
stream with marked blobs, a root commit, deterministic fallback identity, exact
message bytes, and C-style quoted paths. `bridge_git_import` parses one or more
sequential snapshots into an unborn repository, validates global marks and
paths, replaces each working snapshot, and creates ordinary integrity-checked,
optionally signed VCS commits. Smart serving remains explicitly unsupported
until object negotiation is present.

`bridge_git_export_history` emits up to `UV_NODES` commits from a selected
first-parent chain, oldest first, with unique marks across the stream. Sequential
updates to the same Git branch preserve that linear ancestry; merge second
parents are intentionally not represented by this bounded bridge.

`pack.asm` provides the object foundation for Git repositories using
`extensions.objectFormat=sha256`: canonical Git object hashing and a bounded
non-delta PACK v2 writer. Entries use valid zlib stored blocks with Adler-32,
and the completed pack carries its required SHA-256 trailer. Objects are capped
at 65535 bytes and callers must declare the exact object count.

`upload_pack.asm` converts one validated flat-path VCS snapshot into canonical
Git SHA-256 blob, sorted tree, and commit objects, returns the commit OID, and
emits each object once into PACK v2. Nested paths are rejected until recursive
tree construction is implemented, preventing invalid Git tree representations.
