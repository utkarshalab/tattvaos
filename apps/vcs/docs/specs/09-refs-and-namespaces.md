# Refs and Namespaces

- Status: Draft
- Version: 0.0
- Owner: TBD

## Scope

Bookmarks, remote refs, protected namespaces, atomic updates.

## Definitions

## Specification

Local refs use regular files inside `.vcs`: branches are `rh.NAME`, tags are
`rt.NAME`, and each contains one little-endian commit ID. The optional
`.vcs/active` file contains the NUL-terminated active branch name. Ref names are
1..32 ASCII letters, digits, period, underscore or hyphen and cannot begin with
period. All target IDs must resolve to strictly validated commit manifests.

Checkout by branch writes `.vcs/active` and HEAD in the same UXFS transaction as
the worktree replacement. A branch commit publishes new blobs, manifest, format
last-ID/HEAD and branch target together. Numeric checkout removes `.vcs/active`.
Tags never advance. Deleting the attached branch is rejected. Ref creation,
deletion and listing validate the repository and targets before output/mutation.

This is a single local namespace. Remote refs, protected namespaces and access
policies remain outside the current requested local feature scope.

## Test Vectors

Pending host tests cover create/list/delete, invalid names/targets, attached
branch advancement, detached checkout, monotonic IDs after divergence, and
transaction persistence. Validation remains deferred by user request.

## Open Questions
