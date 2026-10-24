# pkg/format — Package Format

**Module:** `pkg/format/`
**Part of:** `pkg/` — Package System

---

## Purpose

Opening and verifying `.upk` packages ([docs/UPK_SPEC.md](../../docs/UPK_SPEC.md)),
which `utasm -f upk` builds and signs.

## Files

```
pkg/format/
├── upk.inc      ← the layout, the opened-package record (upk_pkg_t), the errors
└── upk.asm      ← upk_open, upk_file
```

## What it does

`upk_open(package, length, trusted_keys, key_count, record, allow_unsigned)`
checks a package in memory and stops at the first failure; nothing in the
package runs:

1. the header, and the entry table, string table and manifest exactly where
   the signature covers them;
2. the signature: the signer among the trusted Ed25519 keys (by the SHA-256
   of each key), and Ed25519 over the SHA-256 of header, tables and manifest.
   An unsigned package is refused unless the caller allows it;
3. every entry: its path (parts of `a-z 0-9 . _ -`, no `.` or `..`, each
   once), its kind, its place, its SHA-256;
4. the manifest: known keys only, each once; name, version and kind well
   formed; an entry exactly for an app or a command, naming the one main
   binary.

`upk_file(record, path)` gives a file's bytes and size.

The kernel's boot self-test opens a test package with these, loads its main
binary and runs it (`kernel/exec/selftest.asm`).

## Not yet

Unpacking into `app/` as a signed layer, and granting the manifest's
capabilities: both wait for the filesystem and the package manager
(`app/upm`).

## Dependencies

```text
pkg/format/ depends on:
  → lib/crypto/uhash/sha256/   (file and message digests)
  → lib/crypto/usign/ed25519/  (the signature)
```

---

*pkg/format — Package Format*
*pure x86-64 assembly*
