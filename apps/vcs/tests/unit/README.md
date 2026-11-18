# tests/unit

Executable unit tests cover CLI-independent assembly modules, storage and
protocol orchestration. `test_object_store.py` validates canonical v3 chunk
envelopes and extents; `test_object_index.py` validates catalogs larger than the
legacy 64-record volume, binary lookup, collision-safe copy-on-write merging and
atomic failures. It independently verifies kind-5 generation hashes and rejects
tampered catalogs before lookup. `test_superblock.py` covers the exact format-v3
layout, required features and roots, checksum sealing, tamper rejection,
redundant-slot recovery, torn candidates, monotonic generation selection and
equal-generation split-brain rejection;
`test_chunk_pipeline.py` validates whole-file content
chunking, new-object writes, exact deduplication, collision rejection and
capacity failure. `test_file_object.py` covers multi-page canonical descriptors,
empty and multi-chunk reconstruction, missing or reordered resolved objects,
content corruption, reconstructed hashes and atomic output. The standard
`test_tree_object.py` covers trees larger than the legacy 15-file manifest,
deterministic greedy page boundaries, canonical UTF-8 names, complete IDs,
corrupt/missing chains and atomic decoded views. The standard
`test_ownership.py` suite covers exact file dependency edges, repeated-reference
collapse, canonical catalog ordering, duplicate rejection and explicit
reader-aware reclamation proof. `test_tree_ownership.py` covers root/page and
page/target edges across multiple tree pages, per-owner duplicate collapse and
atomic capacity/corruption failure. `test_ref_catalog.py` validates scalable
variable ref records, canonical names and ordering, alignment padding, kind-1
root and ref-key hashes, bounded record generations, symbolic-form restrictions
and corruption rejection.
`test_commit_object.py` covers canonical root, ordinary and merge commits,
complete ID binding, typed tree/parent ownership edges and atomic bounds.
The standard `make test` target runs these with
`test_publication.py`, which injects failure at every transaction phase and
checks authenticated predecessor transitions and index membership, replay and
rollback rejection, HEAD commit membership, ownership endpoint closure, root
tampering, canonical unique staged sets, candidate-wide index transaction
bounds, exact current-transaction index/staging correspondence, staged
transaction binding, abort, poison,
authenticated envelope-locator binding, canonical ownership batches, complete
physical-envelope and extent-chain validation, transaction-pin coverage,
authenticated ownership-root binding and staged-edge membership, overflow-safe
reservation totals, authenticated ref-root binding, callback order and preflight
atomicity, direct commit-target closure, the required ref-key ownership edge and
symbolic `HEAD` resolution. It also stages a canonical scalable commit and
rejects a transaction missing its required tree dependency edge. The standard
suite rejects an authenticated split state where the selected branch and
superblock HEAD name different valid commits. The standard gate then runs the
remaining module and differential suites.
