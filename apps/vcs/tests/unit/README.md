# tests/unit

Executable unit tests cover CLI-independent assembly modules, storage and
protocol orchestration. `test_object_store.py` validates canonical v3 chunk
envelopes and extents; `test_chunk_pipeline.py` validates whole-file content
chunking, new-object writes, exact deduplication, collision rejection and
capacity failure. The standard `make test` target runs these with the remaining
module and differential suites.
