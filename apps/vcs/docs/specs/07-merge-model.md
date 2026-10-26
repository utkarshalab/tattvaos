# Merge Model

- Status: Draft
- Version: 0.0
- Owner: TBD

## Scope

Three-way tree merge, conflict objects, rename detection, assembly-aware merge.

## Definitions

## Specification

### Commit ancestry

Ordinary commits carry one parent. A merge commit sets the manifest message
length high bit and stores a second parent in the final header qword, as defined
by the storage specification. Old ordinary manifests are unchanged. Ancestry
walks are bounded by the 64-record UXFS volume and reject cycles or forward
parent references. Rebase creates new monotonically numbered commits and never
rewrites an existing manifest.

### Three-way file merge

The implemented merge is content-exact and file-granular. For every path in
the union of base, current HEAD, and target (bounded to 15), it chooses current
when both sides match, target when current matches base, and current when target
matches base. Every other combination is a conflict. Exact blob bytes, not
object IDs, determine equality, so binary files remain safe. For files changed
on both sides, two exact LCS scripts are reduced to base-range/replacement hunks.
Non-overlapping insertions, deletions, and replacements are combined; identical
overlapping hunks are coalesced; other overlaps remain conflicts. A corresponding-
line fallback safely resolves alternative repeated-line alignments when each line
still has an unambiguous unchanged side.

Merge requires a clean working tree and no pre-existing index. `.vcs/merge`
stores target and base IDs, `.vcs/conflicts` stores the bounded unresolved path
list, and `.vcs/index` owns paths read by the final commit. Preparation publishes
these records and the provisional tree together. Continue requires no remaining
conflicts and publishes the two-parent commit while removing operation records.
Abort restores the unchanged pre-merge HEAD and saved attachment, then removes
all merge operation records.

### Rebase replay

Rebase records the first-parent commits after the common base in oldest-first
order, detaches onto the target, and applies each commit as a three-way patch
whose base is its original parent. Successful patches become ordinary one-parent
commits with the original message. Conflicts use the merge conflict record and
pause before committing. Durable progress advances only after the replacement
commit publishes. Completion moves and reattaches the saved branch; old commits
remain immutable and owned by any refs that still name them.
Abort checks out the recorded original tip, restores the saved attachment, and
then removes all rebase operation records.

### Implemented file diff, version 1

`diff_files`: System V AMD64, `rdi` points to `vcs_diff_request` from
`include/diff.inc`. All fields are unsigned 64-bit values:

| Field | Meaning |
|---|---|
| old, old_size | Original byte pointer and length |
| new, new_size | Replacement byte pointer and length |
| scratch, scratch_size | Writable temporary storage, at least 272388 bytes |
| output, capacity | Writable record array and capacity in records |

Returns `rax=VCS_OK`, `rdx=record count`. `VCS_ERR_NO_MEM` means insufficient
scratch or output capacity. For output exhaustion, `rdx` is the exact required
record count; for scratch exhaustion it is zero. `VCS_ERR_USAGE` with `rdx=0`
rejects null required pointers or inputs beyond the supported limits. A null
input pointer is valid only with zero length. A null output pointer is valid
when the result contains no records. A zero-capacity call can query required
output count, but must still supply scratch storage.

Caller-provided pointers must reference valid extents. Inputs may alias each
other. Scratch and output must be disjoint from each other, the request and
both inputs. Scratch is temporary and may change even when a call fails; output
is unchanged on failure. No memory is allocated or retained. Independent callers
can run concurrently using separate request/scratch/output buffers. Standard
SysV register and direction-flag conventions apply.

Each input is limited to 1 MiB and 256 lines. A line includes its terminating
LF if present. Empty input has zero lines; a trailing LF does not introduce an
extra empty line. CR bytes and all other bytes are compared literally, with no
Unicode normalization, decoding, case folding or newline conversion.

The engine computes a longest common subsequence over exact line bytes. It
produces a minimum insertion/deletion script, choosing deletion on ties. A
record is four qwords: `kind, old_offset, new_offset, length`. Kinds are equal
(0), delete (1), insert (2). Equal advances both inputs by `length`; delete
advances only old; insert advances only new. Offsets identify the current input
positions before that record. The result consumes both inputs completely. An
empty script means both inputs are empty; identical nonempty inputs produce
equal records. At most 512 records are required. There is no replace record;
replacement is represented by deletion and insertion.

The fixed-size LCS table bounds working memory and quadratic line comparisons.
The first version deliberately rejects larger inputs; it does not silently
truncate or claim to support arbitrarily large repositories. Line comparison
also depends on line byte length. Hash acceleration and large-file strategies
are deferred until workloads require them.

`vcs_repo_diff` builds the bounded union of paths from HEAD and the worktree,
the persistent staging index, or two validated commit manifests. It resolves
manifest entries to verified blob spans and passes every changed pair through
`diff_files`. Added/deleted files render against `/dev/null`; paths are emitted
as `a/PATH` and `b/PATH`. The union is bounded to 30 paths because each snapshot
contains at most 15. It returns 0 for identical trees, 1 after emitting one or
more changed files, and a VCS error for malformed metadata or exceeded bounds.

The older generic `diff_trees` and `diff_emit` entries remain unavailable and
return `rax=VCS_ERR_UNSUPPORTED`, `rdx=0`; they are not used by Ush.

## Test Vectors

`make test` runs the NASM implementation through an assembly ABI probe. Tests
compare full scripts with a reference LCS, reconstruct the replacement bytes,
check guard canaries and unchanged failure outputs, and verify all callee-saved
registers. Vectors cover empty/repeated lines, binary bytes, UTF-8, CRLF, absent
final newline, 256/257-line boundaries, 1 MiB size limits and exact capacity.
The deterministic generated suite uses 1,800 input pairs. This is focused host
qualification, not native-kernel or QEMU qualification.

## Open Questions
