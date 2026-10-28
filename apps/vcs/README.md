# Utkarsha VCS (working title)

A native, git-interoperable version control system for assembly projects, written entirely in assembly and built directly on UFS.

- Target: Utkarsha OS only (no other operating systems).
- Architectures: x86-64 first; AArch64 and RISC-V 64-bit have reserved places in the tree.
- Assembler: NASM for now; utasm later (see `docs/adr/0001-target-and-assembler.md`).

See `docs/plan/` for the product plan and `docs/specs/` for the Phase 0 specifications. `STRUCTURE.md` explains this layout.

## Implemented slice

`src/cli/cli.asm` provides callable command dispatch: no arguments or `help` /
`--help` returns help; `version` / `--version` returns the development version.
Unknown commands, extra help/version arguments, and NULL argument entries return
`VCS_ERR_USAGE`. This standalone dispatcher remains a library-facing probe;
Ush provides the native repository command adapter. The native archive links
diff, repository/history, staging, refs, checkout, merge, and rebase modules.

Call `cli_main` with System V AMD64 registers `rdi=argc` (including the program
name), `rsi=argv`. It returns `rax=status` and `rdx=static NUL-terminated text`.
The caller displays that text through its frontend. No syscall or UBF/UPK loader
is needed by the dispatcher. Ush uses a separate file-diff command adapter.

Run `sh scripts/test-cli.sh` in an environment with NASM and ld. This runs the
assembly dispatcher in a Linux host harness, checking argument errors, command
results, direct unsupported handlers, and callee-saved registers. This is a
focused host test, not an Utkarsha OS or QEMU integration test.

## Native file diff

`make native` builds `build/vcs-native.o` and `build/libvcs.a` from the implemented
CLI, diff, initialization and history modules. `make test` runs CLI tests and the native diff engine
against an independent Python reference, including 1,800 generated input pairs.
No C API, runtime or Canvas dependency is introduced. Repository initialization
links to the existing UXFS backend; the diff engine remains filesystem-independent.

`diff_files` accepts two in-memory byte spans and returns an exact, deterministic
line edit script. Equal/delete/insert records retain byte offsets, including
CRLF, embedded NULs and missing final newlines. The current bounds are 256 lines
and 1 MiB per input. Scratch and output buffers belong to the caller; insufficient
capacity never partially writes output. See [the diff contract](docs/specs/07-merge-model.md)
and `include/diff.inc` for layouts and register conventions.

Ush implements the local and native synchronization workflows documented below.
The expanded history, staging, refs, merge, rebase, blame, repository-aware
diff, signed patch, and network code is awaiting validation at the user's
request. Bounded Git snapshot/history import and export are available;
smart-protocol serving remains unimplemented. The obsolete generic `diff_trees` and
`diff_emit` ABI entries still return unsupported; `vcs_repo_diff` is the bounded
UXFS-aware implementation used by Ush. No UFS format is invented
by this file-level implementation.

The native sync layer also has a bounded `UVCSBND1` object codec.
`vcs_bundle_export` serializes one validated first-parent commit with its digest,
optional signature, and exact blobs. `vcs_bundle_validate` authenticates the
payload without mutating UXFS. After trusted wire authentication,
`vcs_bundle_publish` atomically remaps the parent, commit, and blob IDs into the
destination object store without moving HEAD or refs. Ush exposes these APIs
through signed patch and native fetch/push/clone commands.

Native TCP setup is non-blocking as well: begin, poll, and close APIs let the
owning Ush task yield during handshake progress. VCS never treats a socket in
`SYN_SENT` as ready to carry repository bytes.

Signed request/response negotiation, cooperative client/server state machines,
single-peer bundle streaming, and first-parent range planning are implemented
internally. Planning matches both native integrity digests and imported
`UVCSMAP1` mappings, emits commits oldest-first, caps a session at 64 bundles,
and rejects divergence. The user-facing adapter is linked only into native Ush;
host Ush intentionally does not link kernel `unet` symbols.

Native `fetch` imports the missing range without moving HEAD. `push` advertises,
reconnects with an exact count, and uploads that range. `clone` requires the
current initialized repository to be unborn. `serve` handles one authenticated
fetch/clone transaction or both connections of one push, then returns to Ush.
Every polling loop invokes the scheduler yield hook; host commands return an
explicit native-only error.

`blame FILE` walks first-parent history and attributes each current line to the
commit where its exact bytes last changed. Each row includes the 16-digit commit
ID and verified signer name; commits without a trusted signature are reported
as `unsigned`. Like the line diff engine, blame is bounded to 256 lines.

`stash` saves the complete changed worktree as a validated hidden snapshot and
restores the original HEAD. The optional message is stored with that snapshot;
repositories that require signed commits use `--sign SEED_FILE`. `stash list`
prints newest first. `apply` replays the newest stash through the same bounded
three-way engine used by cherry-pick, leaving results staged and preserving the
stash. `pop` removes the reference only after a conflict-free apply, while
`drop` removes it without applying. Conflicted pops retain their stash entry.
The stack holds at most 255 entries; removed hidden objects remain retained.

`bisect start GOOD BAD` begins a persistent first-parent binary search, where
GOOD and BAD may be 16-digit IDs or local branches. It requires a clean
worktree, records the original HEAD and branch, then checks out bounded midpoint
commits detached. Mark each result with `bisect good` or `bisect bad`; once the
bounds are adjacent VCS reports and checks out the first bad commit. `status`
prints the current bounds, and `reset` restores the original HEAD and branch.

`git export ID|BRANCH FILE` writes a real Git fast-import stream for one
validated snapshot. Import it in a Git repository with `git fast-import < FILE`.
The stream contains marked blobs, one root commit on `refs/heads/main`, exact
message and file bytes, and safely quoted paths. The UXFS output-file limit is
4096 bytes, so larger snapshots currently fail with a capacity error instead of
producing a truncated stream. `git import FILE [SEED_FILE]` accepts the same
bounded stream in an unborn, otherwise-empty VCS repository and creates a normal
integrity-checked commit. The source stream must be outside the target repository
so it is not mistaken for imported content. A seed is required when signed
commit policy is enabled. Sequential streams from `export-history` are imported
commit-by-commit, replacing each worktree snapshot and reconstructing the same
linear first-parent ancestry. A failed later commit restores the preceding
imported snapshot. Smart serving remains pending.

`git export-history ID|BRANCH FILE` walks the selected commit's complete
first-parent history oldest-first. It emits globally unique blob and commit
marks and sequential commits on `refs/heads/main`; Git therefore reconstructs
the original linear ancestry. Merge second parents are flattened onto the
first-parent view. The same 4096-byte UXFS output bound applies.

History export and smart-pack development share one bounded first-parent
planner. It validates each manifest and returns the selected chain newest-first;
fast-import reverses that plan for oldest-first emission, while upload-pack can
consume the same validated ancestry as Git commit parents are added.

Git commit serialization is also shared behind a bounded request ABI. It emits
canonical tree and optional parent lines, deterministic fallback identity, exact
message bytes, and the resulting SHA-256 object ID. The snapshot pack uses the
same parent-capable encoder with a null parent until history pack orchestration
feeds successive ancestry OIDs.

The smart-serving foundation supports Git SHA-256 object identifiers and
non-delta PACK v2 output with zlib stored blocks, Adler-32 validation, declared
object counts, and a SHA-256 pack trailer. Negotiation and native socket serving
are still pending, so VCS does not yet advertise a cloneable Git endpoint.

The upload-pack object builder converts one validated snapshot into canonical
blobs, recursively nested and sorted trees, and a deterministic root commit. It
returns the Git SHA-256 commit ID and emits the corresponding pack.

Recursive-tree planning is implemented separately: nested paths are validated,
directory prefixes are deduplicated, and explicit depth/parent relationships are
bounded to 64 tree records. Bottom-up tree serialization into upload-pack is the
remaining integration step before nested snapshots become serveable.

Upload-pack now consumes that plan for every snapshot, making it the single
path-safety and hierarchy authority. Nested plans still stop at the explicit
bottom-up serializer boundary rather than being interpreted inconsistently.

Manifest files are now mapped to explicit planned parent directories before
serialization. Missing hierarchy records fail as corruption instead of falling
back to an incorrect root tree.

Direct file and child-directory descriptors can now be sorted with Git's
canonical tree ordering, including the virtual `/` suffix used for subtrees.

Direct-entry collection now joins planned parent mappings with blob and child
tree hashes and returns each directory's descriptors in canonical Git order.

The tree emitter now serializes canonical descriptors into exact Git tree
objects, computes their SHA-256 IDs, and inserts them into PACK v2 with bounded
capacity checks.

Directory orchestration now runs deepest-first, making every child tree hash
available before its parent is encoded and leaving the canonical root ID in the
tree-hash table for commit construction.

Protocol-v2 response encoding now covers capability advertisement,
`object-format=sha256`, `ls-refs` for `HEAD` and the main branch, optional HEAD
symref metadata, and chunked side-band packfile delivery for `fetch`.

Request parsing now recognizes protocol-v2 delimiter packets, validates command
headers and SHA-256 negotiation, and accepts bounded `ls-refs` or single-want
`fetch` requests with standard non-delta negotiation hints.

The Git serving dispatcher now connects advertisement, strict request parsing,
recursive snapshot-pack generation, wanted-OID validation, and protocol-v2
responses. It is allocation-free and buffer bounded. `upload_server.asm` owns
the native nonblocking session, including the Git daemon handshake and
same-connection `ls-refs` to `fetch` transition used by
`vcs git serve PORT [ID|BRANCH] [--clients COUNT|--daemon] [--timeout SECONDS]`.
With no selector the command exports `HEAD`; an explicit commit or branch
publishes that selected snapshot as remote `main`. The safe default serves one
client, `--clients` reuses the listener for a bounded number of sequential
sessions, and `--daemon` serves until Ctrl-C. A malformed client gets
its protocol error and consumes one declared slot without stopping later
clients. A connected client that drops is closed and consumes one slot as well;
listener initialization and shell-yield failures remain terminal. Native Ctrl-C
closes the active sockets and returns shell status 130 without classifying the
interruption as a repository failure.

Once a client is accepted, Git serving applies a 30-second monotonic idle
deadline. Accept, receive, and send progress refresh the deadline; waiting for
the next client does not start it. Expiry closes that client and consumes one
bounded slot when more clients remain. A final timeout closes the listener,
prints a specific diagnostic, and returns status 124. `--timeout SECONDS`
selects a value from 1 through 3600; it applies equally to bounded and daemon
sessions.

## Using diff from Ush

Run `vcs diff FILE1 FILE2` on two regular files in the mounted UXFS volume.
Relative paths use the current directory. Identical files produce no output and
status 0; differing files produce a full line comparison and status 1; invalid
arguments, unavailable storage, missing files/directories or more than 256 lines
produce status 2. Current UXFS files are limited to 4096 bytes each.

The headers `--- FILE1` / `+++ FILE2` identify the first and second arguments.
Lines use space/equal, minus/delete and plus/insert prefixes. A separate marker
identifies lines without a final LF. Backslashes, control bytes, CR and non-ASCII
bytes are rendered as `\xHH`, so stored terminal escape sequences cannot execute.
This is a readable byte-preserving comparison, not a standard unified patch.
UTF-8 bytes are escaped rather than interpreted in this initial terminal view.
No repository or file is modified. `vcs`, `vcs help` and `vcs --help` show usage.

Inside a repository, `vcs diff` compares the working tree with HEAD,
`vcs diff --staged` compares only indexed paths with HEAD, and
`vcs diff ID1 ID2` compares two validated commit snapshots. Added and deleted
files use `/dev/null`; other headers use `a/PATH` and `b/PATH`. All modes reuse
the exact line engine and byte escaping above. Repository-aware differences
return status 1, identical trees return 0, and malformed metadata returns 2.
When both two-argument operands are 16-digit commit IDs they select commit mode;
all other two-operand invocations retain the original regular-file comparison.

`make -C apps/ush test` includes persistent-volume integration tests for paths,
statuses/chaining, exact rendering, binary data, line limits and unchanged image
bytes. The adapter is part of `ush-native.o`. Earlier diff/init host checks
passed; the subsequent history changes have not been built or tested yet.
Production kernel/QEMU validation remains pending.

## Initialize a repository

`vcs init [DIRECTORY]` creates `.vcs/format` in an existing UXFS directory;
omitting the argument uses the current directory. Initialization preserves
working files, publishes the directory/header in one volume commit, and is
idempotent for supported metadata. Partial, foreign or unknown-version metadata
is rejected without replacement. The initializer returns command status 0 on
success and 2 on failure. After I/O failure the volume requires remount; the
write may already have completed, so rollback is not promised.

See [the bootstrap storage format](docs/specs/04-storage-layout.md). The native
`vcs_repo_init` API is implemented in `src/store/repository.asm`; its explicit
UXFS dependencies are resolved by the caller, including the Ush native build.
Its original implementation was tested with the real volume backend and
torn-write/flush injection. The history-aware update is awaiting validation.

## Local history

From a repository or any subdirectory:

```text
vcs status
vcs check
vcs commit "Describe the changes"
vcs commit -m "Short title" -m "Longer explanation"
vcs commit -F /commit-message
vcs log
vcs log --oneline
vcs show [HEAD|16-HEX-ID]
vcs blame FILE
vcs stash [MESSAGE]
vcs stash --sign SEED_FILE [MESSAGE]
vcs stash list
vcs stash apply
vcs stash pop
vcs stash drop
vcs bisect start GOOD BAD
vcs bisect good
vcs bisect bad
vcs bisect status
vcs bisect reset
vcs git export ID|BRANCH FILE
vcs git export-history ID|BRANCH FILE
vcs git import FILE [SEED_FILE]
vcs git serve PORT [ID|BRANCH] [--clients COUNT|--daemon] [--timeout SECONDS]
vcs restore PATH
vcs add PATH... | --all
vcs reset PATH... | --all
vcs staged
vcs branch NAME [ID]
vcs tag NAME [ID]
vcs refs
vcs checkout ID|BRANCH --force
vcs merge ID|BRANCH
vcs conflicts
vcs resolve PATH
vcs merge --continue MESSAGE
vcs merge --abort
vcs rebase ID|BRANCH
vcs rebase --continue
vcs rebase --abort
vcs identity [NAME SEED_FILE]
vcs identity --rotate NAME SEED_FILE
vcs identity --revoke NAME
vcs policy [require-signed|allow-unsigned]
vcs commit --sign SEED_FILE "MESSAGE"
vcs commit --sign SEED_FILE -m "TITLE" [-m "BODY" ...]
vcs commit --sign SEED_FILE -F FILE
vcs sign [HEAD|16-HEX-ID] SEED_FILE
vcs verify [HEAD|16-HEX-ID]
vcs check --signatures
vcs cherry-pick ID [--sign SEED_FILE]
vcs revert ID [--sign SEED_FILE]
vcs cherry-pick|revert --continue [--sign SEED_FILE]
vcs cherry-pick|revert --abort
vcs patch export ID FILE SEED_FILE
vcs patch inspect FILE
vcs patch import FILE [SEED_FILE]
vcs patch apply FILE [SEED_FILE]
vcs remote
vcs remote add NAME IPV4 PORT
vcs remote remove NAME
vcs fetch REMOTE SEED_FILE [REF]
vcs push REMOTE SEED_FILE [REF]
vcs clone REMOTE SEED_FILE [REF]
vcs serve PORT SEED_FILE
```

`patch export` writes a signed wire frame containing one validated first-parent
commit. `inspect` verifies the trusted transport signer, bundle structure,
object digest, and embedded commit signature without changing the repository.
`import` atomically remaps the commit into the local object store without moving
HEAD. `apply` imports it and then runs the normal cherry-pick/conflict workflow.
The optional seed locally signs remapped and applied commits; it is required
when repository policy requires signatures. Patch files currently inherit
UXFS's 4096-byte file limit; larger bundles are reserved for streamed `unet`
transfer.

`remote add` stores a validated literal IPv4 endpoint under repository metadata;
remote names use the same bounded safe alphabet as refs. `remote` lists names
and endpoints, while `remote remove` deletes one record atomically. Hostname and
DNS handling remain deferred until the native resolver is integrated.

`status` compares working files with the current snapshot and displays `A`, `M`
and `D` for added, modified and deleted paths. Status returns 0 even when files
have changed. `add` records selected repository-relative paths in a persistent
index; `add --all` includes additions, modifications, and tracked deletions.
`reset` removes paths from the index, `reset --all` clears it, and `staged`
lists it. Once an index exists, `commit` snapshots only staged paths and retains
HEAD content for unstaged paths; a successful commit clears the index. Without
an index, commit-all remains supported. It accepts a nonempty message up to
215 bytes, including newline bytes. Repeated `-m` arguments join paragraphs
with a blank line (`LF LF`). `-F FILE` reads exact bytes from a regular UXFS
file, so Uedit can compose multiline messages. Empty, oversized or NUL-containing
message files are rejected. `-m` and `-F` cannot be mixed. Plain quoted messages
still work. Ush does not gain shell-wide escape expansion or interactive quote
continuation; use repeated `-m` or a message file in an interactive terminal.

Repository format version 2 stores a SHA-256 integrity record for every commit.
The digest uses `lib/crypto/uhash/sha256` over a domain separator, the exact
manifest, and every referenced blob in manifest order. Normal history reads
verify it. `vcs check` verifies every allocated commit and fails on changed or
missing objects. This is tamper detection and is also the message authenticated
by optional signatures; it is not encryption.

`vcs identity NAME SEED_FILE` registers the repository's active signed
identity. The seed file must contain exactly 32 bytes. VCS derives the public
key through `lib/crypto/usign/ed25519` and stores only the name and public key;
the private seed is never copied into `.vcs`. `vcs identity` displays the name
and full public key. `vcs sign [HEAD|ID] SEED_FILE` requires a seed matching that
identity and creates one durable Ed25519 signature sidecar. `vcs verify [HEAD|ID]`
first verifies the commit manifest, blobs, and SHA-256 digest, then checks the
signature against a trusted identity. `identity --rotate` archives the previous
public identity before activating the replacement, so its historical signatures
remain verifiable. `identity --revoke NAME` creates a durable key revocation;
revoked signatures fail verification. `vcs check --signatures` requires and
verifies a signature for every commit. `vcs policy require-signed` rejects every
new commit lacking a seed, including merge, rebase, cherry-pick, and revert
commits; `allow-unsigned` restores the default. `commit --sign` publishes the
manifest, digest, signature, HEAD, and attached branch update atomically.
It supports the same plain, repeated `-m`, and `-F` message forms.
Seed-file protection remains the user's responsibility because UXFS does not
yet provide file permissions.

`log` prints local hexadecimal commit numbers and indented multiline messages,
newest first. Literal LF bytes retain line breaks; other control/non-ASCII bytes
and backslashes are escaped. `log --oneline` prints each complete message on one
physical line, escaping LF as `\x0a`. Stored message bytes remain unchanged.
Commands discover the nearest `.vcs` directory by walking upward
from the current directory, and reject malformed repository metadata.

`show` validates the requested commit and prints its full multiline message,
then lists each snapshotted path with its byte size. Omitting the argument or
using `HEAD` selects the current commit. Explicit IDs use the same 16-digit
hexadecimal form printed by commit and log. Blob contents are not dumped.

`restore PATH` replaces one tracked file with its exact HEAD blob, recreating a
deleted file when its parent directory remains. It never restores an untracked
path or directory. `checkout ID|BRANCH --force` atomically replaces regular
working files with a complete snapshot and moves HEAD. Explicit `--force` is
mandatory because uncommitted file changes can be destroyed. Empty directories
are retained and are not restored because this format tracks regular files only.
Missing parent directories and file/directory path conflicts reject checkout.

Branches and tags are durable refs named with 1..32 ASCII letters, digits,
period, underscore or hyphen; a leading period and path separators are rejected.
`branch` and `tag` default to HEAD or accept a 16-digit commit ID. `refs` lists
both kinds. `branch -d NAME` and `tag -d NAME` delete them. Checking out a branch
attaches HEAD; subsequent commits advance that branch atomically with the commit.
Checking out an ID detaches HEAD. An attached branch cannot be deleted. Tags do
not move. Commit allocation IDs remain monotonic across divergent branches,
while log follows each manifest's explicit parent.

`merge` requires a clean working tree and an empty staging index. It computes a
bounded three-way merge from the nearest common ancestor. Whole-file changes on
only one side and byte-identical results are applied automatically; overlapping
file edits first use an exact corresponding-line three-way merge, so independent
line replacements merge automatically. Non-overlapping insert/delete hunks also
merge; competing overlapping edits and modify/delete pairs remain explicit conflicts.
Preparation atomically writes the working
result, staging index, target/base state, and conflict list. `conflicts` lists
unresolved paths. After editing, creating, or deleting the desired result,
`resolve PATH` acknowledges it. `merge --continue MESSAGE` requires an empty
list, creates a true two-parent commit, and removes operation metadata in the
same commit transaction. Merge messages are limited to 207 bytes. Rename
detection is deferred; paths remain the explicit identity boundary.
`merge --abort` restores the unchanged pre-merge HEAD snapshot and branch
attachment, then removes merge, conflict, and index state.

`rebase` replays the current branch's nonempty first-parent suffix onto a commit
or branch, preserving each original message while allocating new monotonic IDs.
It requires a clean working tree and empty index. Durable `.vcs/rebase` state
records the original tip, target, replay order, progress, and prior branch
attachment before checkout. Non-conflicting commits replay automatically. A
conflict uses the same `conflicts` and `resolve` commands; `rebase --continue`
commits the resolved patch and resumes. Completion atomically moves and
reattaches the original branch. Existing commits are never rewritten or freed.
`rebase --abort` force-restores the saved original snapshot and branch attachment,
then removes the rebase, conflict, and index records.

`cherry-pick ID` applies one commit through the same three-way replay
engine and preserves its message. `revert ID` applies the inverse patch and uses
`Revert ID` as its message. Both persist `.vcs/pick` before changing the working
tree, share `conflicts` and `resolve`, and support `--continue` and `--abort`.
Root commits use the replay engine's bounded in-memory empty manifest as their base.
When signed commits are required, pass `--sign SEED_FILE` on the start or
continuation that creates the commit.

Snapshots exclude every `.vcs` path component; empty directories are not tracked.
An optional root `.vcsignore` file supplies literal repository-relative paths,
one per line. A trailing slash ignores that directory prefix. Blank lines and
lines beginning `#` are ignored; globbing, negation and per-directory rule files
are not implemented. The root `.vcsignore` remains trackable. Invalid control,
NUL or over-239-byte rule lines make repository operations reject the metadata.
Files inside nested repositories are included as ordinary working files, while
their metadata is excluded. At most 15 files, each up to 4096 bytes, fit a
snapshot. The shared UXFS volume has 64 records; each commit needs one manifest,
one SHA-256 integrity record, and one blob per added/modified file. A signed
commit additionally owns one signature record. Unchanged blobs are reused.
Commit preparation checks capacity and name collisions before modifying storage.
All new objects and the HEAD update are published in one volume transaction.

The first empty commit is allowed. Later unchanged commits print `Nothing to
commit` without allocating objects or updating storage. History objects use
explicit ownership through manifests and refs; no tracing/background garbage
collector exists. Removal requires an explicit operation that proves an object
has no live owner. History rewriting never mutates or frees an existing object.
Timestamps and Git interoperability are outside the current scope.
The single repository identity is a local trust anchor, not a certificate or
remote identity claim. Local IDs are sequence numbers, not cryptographic content hashes. The
private on-disk format is specified in [Storage Layout](docs/specs/04-storage-layout.md).

**Validation deferred:** the new status/commit/log implementation, initialization
update, and added native/host regression tests have not been run. The pending
commands are `make -C apps/vcs test` and `make -C apps/ush test`, followed by
production kernel/QEMU integration when validation resumes.
