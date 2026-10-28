# src/bridge

Git bridge: fast-import interchange, Git SHA-256 object generation, and bounded
protocol-v2 upload serving.

`bridge_git_export` emits one validated VCS snapshot as a real Git fast-import
stream with marked blobs, a root commit, deterministic fallback identity, exact
message bytes, and C-style quoted paths. `bridge_git_import` parses one or more
sequential snapshots into an unborn repository, validates global marks and
paths, replaces each working snapshot, and creates ordinary integrity-checked,
optionally signed VCS commits. Smart serving exports one selected snapshot and
therefore accepts only that advertised commit as a fetch target.

`bridge_git_export_history` emits up to `UV_NODES` commits from a selected
first-parent chain, oldest first, with unique marks across the stream. Sequential
updates to the same Git branch preserve that linear ancestry; merge second
parents are intentionally not represented by this bounded bridge.

`pack.asm` provides the object foundation for Git repositories using
`extensions.objectFormat=sha256`: canonical Git object hashing and a bounded
non-delta PACK v2 writer. Entries use valid zlib stored blocks with Adler-32,
and the completed pack carries its required SHA-256 trailer. Objects are capped
at 65535 bytes and callers must declare the exact object count.

`upload_pack.asm` converts one validated VCS snapshot into canonical Git SHA-256
blob, recursive tree, and commit objects, returns the commit OID, and emits each
object once into PACK v2. Tree planning and emission handle nested paths
deepest-first.

`tree.asm` supplies the recursive-tree planner: it validates every path,
deduplicates directory prefixes, records depth and parent indices, and bounds a
snapshot to 64 Git tree records. Upload-pack consumes the plan bottom-up so
nested paths are represented by canonical child-tree objects.

The planner also maps every manifest file to its exact directory record. This
removes prefix guessing from the serializer and makes root files, nested files,
and missing/corrupt parent records explicit before object bytes are emitted.

Direct-entry descriptors now have a canonical in-place sorter. It implements
Git's tree comparison rule by treating directory names as if suffixed with `/`
and file names as NUL-terminated, making tree byte order deterministic.

The planner can now collect one directory's direct files and child directories
into descriptors, attach their blob/tree hashes, derive child basenames, enforce
capacity, and return the entries already in canonical Git order.

Canonical descriptors can now be encoded into exact Git tree bytes (`100644`
files and `40000` subtrees), SHA-256 object-hashed, and appended directly to the
active PACK v2 writer. Capacity and malformed names fail before partial success.

The plan emitter now walks maximum depth back to root, gathers each directory's
direct entries, emits and hashes the tree, and stores that hash for its parent.
After completion `tree_hashes[0]` is the canonical root tree ID.

`upload_protocol.asm` encodes Git protocol-v2 capability advertisement,
SHA-256 `ls-refs` output for `HEAD` and `refs/heads/main`, optional
`symref-target:refs/heads/main` metadata, and chunked side-band `fetch` packfile
responses. All records use bounded pkt-lines and explicit flushes.

`upload_request.asm` parses protocol-v2 command headers and delimiter packets,
requires SHA-256 object format, accepts bounded `ls-refs` filters, and validates
one 64-hex `want` plus `done` for fetch. Standard `thin-pack`, `no-progress`,
`ofs-delta`, and `include-tag` hints are accepted because the returned complete
non-delta snapshot pack satisfies them; depth and object-filter requests remain
unsupported and are not advertised.

`ref-prefix` arguments are applied to the exported `HEAD` and
`refs/heads/main` names. Multiple prefixes form a union, an explicit nonmatching
filter produces an empty flushed response, and an unfiltered request returns
both refs.

`bridge_git_serve` now composes advertisement, request parsing, recursive pack
generation, OID validation, `ls-refs`, and `fetch` responses behind a bounded
two-phase buffer API. Native socket polling remains the outer transport owner.

`upload_server.asm` owns that native transport. It accepts one `git://` client,
validates the bounded `git-upload-pack /` daemon request and its `version=2`
parameter before advertising, handles partial nonblocking I/O, serves one
`ls-refs` followed by `fetch` on the same protocol-v2 connection, and closes
both sockets on every terminal path. A direct `fetch` is also accepted, while
repeated reference discovery is rejected as an invalid session sequence.
