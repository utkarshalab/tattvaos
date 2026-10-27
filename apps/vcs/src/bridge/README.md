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
