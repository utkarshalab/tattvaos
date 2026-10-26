# src/merge

Diff and three-way merge, assembly-aware tokenizer, first-class conflict objects, content-type classifier.

Implemented: bounded, exact LF-line diff in `diff.asm`, with caller-owned scratch
and output buffers. See `include/diff.inc` and `docs/specs/07-merge-model.md`.

`integrate.asm` implements bounded whole-file three-way merge, persistent
conflict paths, explicit resolution, and two-parent continuation on UXFS.
`rebase.asm` persists and replays first-parent commit suffixes through that same
three-way engine, including branch reattachment and conflict continuation.
`pick.asm` reuses the replay engine for durable cherry-pick and inverse revert,
including root commits through the bounded empty-manifest base. Merge, rebase,
pick and revert continuations all route through the central optional signed
commit path rather than implementing their own object publication.
`repo_diff.asm` maps worktree, index, and commit trees onto the exact line
engine and renders bounded terminal-safe patches. The obsolete generic
`diff_trees` and `diff_emit` library entries still return unsupported.
Tokenization, semantic line splicing, rename detection, and classification are
not part of this conservative merge path.
