# Fuzz Corpus

The fuzzers make their own inputs, from fixed seeds, so a failure repeats:

- `tests/unit/test_fuzz.asm` (a host suite, run by `make check`): random
  messages from a client holding every capability, real handles from the
  server's replies put back into them, and random raw input records of every
  type. The server must not crash, and a second client must still be
  answered.
- `tests/host/fuzz_media.py` (run by `make check`, longer by `make fuzz`):
  small valid images of every format `image_decode` reads, made with Pillow,
  mutated and decoded by `host_decode`. A crash or a hang fails; the mutant is
  kept as `fuzz_media_fail_*` in the working directory.

A failing input found by either becomes a regression test in the suite of
the code it broke; crashing inputs are not committed here.
