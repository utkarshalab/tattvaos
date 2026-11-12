# tests/unit

Executable unit tests cover CLI-independent assembly modules, storage and
protocol orchestration. `test_object_store.py` validates canonical v3 chunk
envelopes and extents; `test_object_index.py` validates catalogs larger than the
legacy 64-record volume, binary lookup, collision-safe copy-on-write merging and
atomic failures; `test_chunk_pipeline.py` validates whole-file content
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
atomic capacity/corruption failure. The standard `make test` target runs these with
`test_publication.py`, which injects failure at every transaction phase and
checks abort, poison, callback order and preflight atomicity, plus the remaining
module and differential suites.
