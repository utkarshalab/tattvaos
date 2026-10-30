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

`history_plan.asm` owns the shared first-parent walk used by history export and
the developing history-aware upload pack. It validates every manifest, bounds
the chain by caller capacity, and returns commit IDs newest-first so consumers
can choose forward or reverse emission without repeating ancestry validation.

`commit.asm` owns canonical Git SHA-256 commit-body serialization. A bounded
request supplies tree OID, optional parent OID, exact message bytes, output
capacity, and hash destination. Snapshot upload-pack now uses this encoder with
no parent; history upload will feed the previous encoded commit OID.

`history_pack.asm` now performs that history upload. It preflights the complete
first-parent plan and declared object count before opening PACK v2, then walks
oldest-first, emits each snapshot's validated blobs and recursive trees, and
feeds every generated commit OID into its child's parent line. Repeated objects
are removed by the bounded unique-pack writer before the final object count and
checksum are published; capacity exhaustion fails the whole response.

Reference discovery uses the same canonical history encoder in hash-only mode.
It computes the advertised tip through blob, recursive-tree, and parent-linked
commit hashing without allocating or serializing a PACK; only `fetch` pays the
bounded pack-construction cost.

`pack.asm` provides the object foundation for Git repositories using
`extensions.objectFormat=sha256`: canonical Git object hashing and a bounded
non-delta PACK v2 writer. Entries use valid zlib stored blocks with Adler-32,
and the completed pack carries its required SHA-256 trailer. Exact-count mode
serves snapshots; unique mode accepts a bounded candidate maximum, removes
duplicate OIDs, and patches the final count before hashing. Objects are capped
at 65535 bytes.

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
responses. Fetch advertises `wait-for-done`, `ref-in-want`, `sideband-all`,
`filter`, and `shallow`, matching the bounded negotiation model, direct main-ref
requests, multiplexing, partial clones, and depth-limited history. All records
use bounded pkt-lines and explicit flushes.

The advertisement also publishes `server-option`. Each command may carry up to
eight `server-option=<value>` headers with 1..128 value bytes; empty values,
NUL, embedded LF, and overflow are rejected. Valid options are intentionally
ignored until Tattva VCS defines option-specific behavior.

`upload_request.asm` parses protocol-v2 command headers and delimiter packets,
requires exactly one SHA-256 object-format header, accepts at most one printable
bounded `agent=` header, rejects unadvertised header extensions, accepts bounded
`ls-refs` filters plus the standard `symrefs`, `peel`, and `unborn` arguments,
and validates either one 64-hex `want` or one `want-ref` naming advertised
`HEAD` or `refs/heads/main`, and up to 64 ordered SHA-256 `have` lines. A fetch
with `done` produces the pack response; a round with haves but no `done` produces
only bounded acknowledgments. This accepts initial clones and incremental client
negotiations with a bounded common-history cut.
Standard `thin-pack`, `no-progress`, `ofs-delta`, and `include-tag` hints are
accepted once each because the returned complete non-delta history pack
satisfies them; duplicate hints are rejected with the other duplicate request
options instead of consuming the bounded request buffer repeatedly.
The advertised `wait-for-done` hint is accepted once. The bounded depth and
object-filter forms described below are advertised and parsed explicitly.

Negotiation-only rounds return an `acknowledgments` section containing an `ACK`
for every canonical common `have` in request order, or one `NAK` when none are
common, followed by a flush. With `wait-for-done`, a missing common base, or
an invalid declared client boundary, they never emit `ready` or a pack and the
native server keeps the same connection open or rejects the invalid boundary.
Otherwise a canonical common base permits an `acknowledgments` section containing
`ready`, a delimiter, and the pack response in the same round; that session
becomes terminal. Depth-limited fetches may include `shallow-info` after `ready`.
Existing shallow clients receive the same validated absolute or relative
`unshallow`/replacement-`shallow` transition used by a `done` request. A later
request with `done` also omits acknowledgments and proceeds directly to the pack.

The bounded filter implementation accepts `filter blob:none`, `filter tree:N`
for N=0..255, `filter blob:limit=N[kmg]`, and
`filter object:type=(tag|commit|tree|blob)`. Decimal blob limits use bytes;
suffixes expand in binary units and saturate above the 65535-byte object ceiling.
Blob contents, recursive trees, and commits are still encoded and hashed so every
identity remains canonical. `blob:none` omits all blobs; `tree:N` omits trees and
blobs at depth N or deeper; and `blob:limit` omits blobs whose size is at least
the expanded limit. Object-type filtering emits matching supporting objects;
the explicitly requested tip commit remains present for connectivity, while
nonmatching parent commits may be omitted. `combine:` intersects two through
four unique supported filters.
Each component is fully percent-decoded into a 64-byte fixed buffer before
validation. Invalid escapes, decoded NUL, overflow, empty, duplicate, nested,
and unknown components are rejected.

Shallow fetch accepts exactly one `deepen N` with `N` in 1..255. The pack limit
is the tighter of N and the common-history cut. When depth truncates history,
the oldest emitted canonical commit retains its real parent and is reported in
a `shallow-info` section before wanted refs and pack data. Requests that exceed
available or missing history need no shallow marker. `deepen-relative` accepts
exactly one client `shallow` OID, requires it to match the canonical first-parent
chain, and extends the requested depth from that boundary. The response marks
the old boundary `unshallow` and reports a new `shallow` boundary when history
still remains. Relative packs deliberately repeat the already-held prefix so
they remain complete and non-delta. Ordinary `deepen N` also accepts one
canonical client boundary, treats N as an absolute tip depth, and returns the
same boundary-change records. If the absolute boundary is unchanged, the
redundant `unshallow`/`shallow` pair is suppressed. Other shallow arguments are
rejected.

All validated `have` identities are retained in request order as one immutable
bounded view. After an acknowledgment-only round, its deduplicated view becomes
connection state and is merged with later `have` lines up to 64 unique OIDs.
The history encoder records every canonical first-parent commit OID and can
locate the newest matching history index across the accumulated view, providing
a trustworthy cut point for the incremental pack builder without trusting
client hashes. A new or rearmed client starts with an empty retained view.
Only newer commits and their snapshot objects are emitted; the first missing
commit retains the common OID as its parent. A client already holding the tip
receives a valid zero-object pack with the ordinary checksum trailer.

When `sideband-all` is requested, every ordinary response pkt-line—including
section headers and wanted-ref records—carries channel 1. Delimiter and flush
packets remain unmodified, and pack chunks retain their existing channel byte.

`want-ref` fetches accept either advertised `HEAD` or `refs/heads/main` and emit
the required `wanted-refs` section with each requested name, canonical SHA-256
tip, and a delimiter before the side-band packfile section. A fetch may request
one or both unique names; duplicates are rejected. One object-ID `want` may be
combined with those refs, but it still must equal the selected canonical tip.

`ref-prefix` arguments are applied to the exported `HEAD` and
`refs/heads/main` names. Multiple prefixes form a union, an explicit nonmatching
filter produces an empty flushed response, and an unfiltered request returns
both refs. Prefixes are classified by whether they match neither ref, `HEAD`,
main, or both; a second prefix with the same result is rejected as redundant,
bounding the union to four semantic classes without retaining client strings.
`peel` produces no attribute because this bounded endpoint exports
only commit refs, while `unborn` is accepted consistently with the advertised
capability and produces no marker for the required existing selected commit.
Duplicate or unknown arguments are rejected.

`bridge_git_serve` now composes advertisement, request parsing, hash-only tip
discovery for `ls-refs`, common-history incremental pack generation and tip-OID
validation for `fetch`, and both responses behind a bounded two-phase buffer
API. Native socket polling remains the outer transport owner.

`upload_server.asm` owns that native transport. It accepts one `git://` client,
validates the bounded `git-upload-pack /` daemon request, an optional printable
255-byte `host=` value, the required empty separator, and an exact `version=2`
extra parameter before advertising. NUL-delimited unknown extras are bounded and
ignored as Git requires; duplicate versions, unterminated fields, and substring
matches are rejected. The server handles partial nonblocking I/O and serves one
`ls-refs` followed by `fetch` on the same protocol-v2 connection, and closes
both sockets on every terminal path. A direct `fetch` is also accepted, while
repeated reference discovery is rejected as an invalid session sequence.
Acknowledgment-only fetch responses return to receive state, allowing bounded
multi-round have exchange before either `ready` or `done` produces the terminal
pack response. Each continuation promotes its deduplicated have view so the
terminal pack cut includes common history learned in earlier rounds. A client
may complete at most 64 acknowledgment-only continuations, matching the unique
have capacity; a following terminal `done` remains valid, while another
continuation receives a protocol error. Rearming clears the round count.
Empty-queue send/receive results are retried only while the accepted socket is
still established, so a peer FIN or failed connection terminates the command
instead of leaving Ush in a permanent poll loop.

Malformed and unsupported requests receive a bounded Git `ERR` pkt-line before
the connection closes. The server preserves and returns the original VCS error
after the nonblocking error response is fully sent; unwritable transport errors
still terminate immediately.

After a terminal response, `git_upload_server_rearm` closes only the client and
returns the retained listener to its accept state. Ush uses this for successful
sessions and delivered protocol rejections in bounded `--clients COUNT` and
continuous `--daemon` modes. It can also discard a failed or timed-out
post-accept client without reopening the listener; pre-accept and invalid states
cannot rearm. The default remains one session, and daemon mode relies on the
native Ctrl-C cancellation path for clean termination.

The server publishes a monotonic progress generation and a client-presence
query without exposing mutable session storage. Ush uses them with its native
monotonic clock hook to enforce an idle deadline only after accept; each accepted
connection, receive, send, or rearm transition advances the generation.
