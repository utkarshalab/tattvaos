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

Ush implements the local workflow documented below. The expanded history,
staging, refs, merge, rebase, and repository-aware diff code is awaiting
validation at the user's request. Git-compatible patch serialization and Git
interchange remain unimplemented. The obsolete generic `diff_trees` and
`diff_emit` ABI entries still return unsupported; `vcs_repo_diff` is the bounded
UXFS-aware implementation used by Ush. No UFS format is invented
by this file-level implementation.

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
```

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
Timestamps and network/Git interoperability are outside the current scope.
The single repository identity is a local trust anchor, not a certificate or
remote identity claim. Local IDs are sequence numbers, not cryptographic content hashes. The
private on-disk format is specified in [Storage Layout](docs/specs/04-storage-layout.md).

**Validation deferred:** the new status/commit/log implementation, initialization
update, and added native/host regression tests have not been run. The pending
commands are `make -C apps/vcs test` and `make -C apps/ush test`, followed by
production kernel/QEMU integration when validation resumes.
