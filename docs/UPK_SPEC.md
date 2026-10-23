# Utkarsha Package (UPK)

> How software arrives on Utkarsha OS: one signed file holding a program's
> UBF binaries ([UBF_SPEC.md](UBF_SPEC.md)), its resources and default
> configuration, and a plain-text manifest. Built and signed by
> `utasm -f upk`, verified and installed by the package manager (`app/upm`).

**Status:** version 1, draft.

## Contents

1. [Model](#1-model)
2. [File layout](#2-file-layout)
3. [Header](#3-header)
4. [Entry table](#4-entry-table)
5. [Manifest](#5-manifest)
6. [Signature](#6-signature)
7. [Installing](#7-installing)
8. [Building with utasm](#8-building-with-utasm)

---

## 1. Model

- **A package is a signed list of files.** The signature covers the manifest
  and the SHA-256 of every file, so changing any byte of any file, adding a
  file or reordering them breaks it.
- **The manifest is the package's identity** (FS_LAYOUT.md §3.5): name,
  version, kind, the capabilities and models it asks for, what it depends on.
  It is plain `key = value` text, so it can be read and reviewed by hand.
- **Installing never runs package code.** Verification and unpacking are done
  entirely by the package manager; nothing in the package executes until it
  is installed and launched.

All multi-byte fields are little-endian.

## 2. File layout

```
+---------------------------+  0
| header (144 bytes)        |
+---------------------------+  entry_off
| entry table               |  entry_count x 64 bytes
+---------------------------+  strtab_off
| string table              |  file paths, NUL-terminated
+---------------------------+  manifest_off
| manifest (UTF-8 text)     |  manifest_size bytes
+---------------------------+  (16-byte aligned)
| file contents             |  each entry's bytes at its data_off
+---------------------------+  file_size
```

## 3. Header

The header is 144 bytes.

| Offset | Size | Field | Meaning |
|---|---|---|---|
| 0x00 | 4 | `magic` | `"UPK\0"` = `0x004B5055` |
| 0x04 | 2 | `version` | 1 |
| 0x06 | 2 | `header_size` | 144 |
| 0x08 | 4 | `flags` | bit 0: signed; others 0 |
| 0x0C | 4 | `entry_count` | 1–4096 |
| 0x10 | 4 | `entry_off` | |
| 0x14 | 4 | `strtab_off` | |
| 0x18 | 4 | `strtab_size` | |
| 0x1C | 4 | `manifest_off` | |
| 0x20 | 4 | `manifest_size` | at most 64 KiB |
| 0x24 | 4 | reserved | 0 |
| 0x28 | 8 | `file_size` | total package length |
| 0x30 | 32 | `signer` | SHA-256 of the signer's Ed25519 public key; zero if unsigned |
| 0x50 | 64 | `signature` | Ed25519 signature (§6); zero if unsigned |

## 4. Entry table

Entry (64 bytes):

| Offset | Size | Field | Meaning |
|---|---|---|---|
| 0x00 | 4 | `path_off` | offset of the path in the string table |
| 0x04 | 4 | `kind` | 1 main binary (UBF), 2 library (UBF), 3 command (UBF), 4 resource, 5 default configuration, 6 model data |
| 0x08 | 8 | `data_off` | where the file's bytes start |
| 0x10 | 8 | `size` | file length |
| 0x18 | 32 | `sha256` | SHA-256 of the file's bytes |
| 0x38 | 8 | reserved | 0 |

Paths are relative to the package's install folder, use `/`, and contain
only lower-case letters, digits, `.`, `_` and `-` in each part; `..`, empty
parts and absolute paths are refused. Exactly one entry of kind 1 is allowed,
and only in an application package.

## 5. Manifest

UTF-8 text, one `key = value` per line. `#` starts a comment; blank lines
are ignored; keys are lower case; a key appears at most once.

```
name         = calculator
version      = 1.2.0
kind         = app
title        = Calculator
publisher    = Utkarsha Labs
entry        = main
capabilities = file.read:user/files, file.write:user/files
models       =
depends      = umath >= 1.0
min_os       = 0.0.1
```

| Key | Required | Meaning |
|---|---|---|
| `name` | yes | the `<app>` / `<lib>` / `<command>` name: lower case, 1–32 of `a-z 0-9 -`; not a reserved name (FS_LAYOUT.md §10) |
| `version` | yes | `major.minor.patch` |
| `kind` | yes | `app`, `lib` or `cmd` |
| `title` | no | display name |
| `publisher` | no | who built it |
| `entry` | app, cmd | path of the kind-1 (or kind-3) entry |
| `capabilities` | no | comma-separated grants requested beyond the defaults (FS_LAYOUT.md §4.2) |
| `models` | no | comma-separated base models the app reads from `app/model/` |
| `depends` | no | comma-separated `name >= version` library requirements |
| `min_os` | no | lowest OS version the package supports |

Unknown keys are refused, so a typo cannot silently drop a requirement.

## 6. Signature

The signed message is the SHA-256 of, in order:

1. the 144-byte header with `signature` set to zero,
2. the entry table,
3. the string table,
4. the manifest.

Since each entry carries its file's SHA-256, the signature covers every byte
of the package. The signature is Ed25519 over that 32-byte digest; `signer`
names the key, which must be in `sec/trust/` with the right to sign packages.

## 7. Installing

The package manager installs a package from `keep/upd/` in this order and
stops at the first failure, leaving nothing behind:

1. Check the header, the tables' bounds and `file_size`.
2. Verify the signature against `sec/trust/`; an unsigned package installs
   only when admin policy allows it.
3. Parse the manifest; check `name`, `kind`, `entry`, the dependencies and
   `min_os`.
4. Check every entry's path and SHA-256, and every UBF entry's own header and
   digest.
5. Unpack into a new signed layer: `app/<name>/` for an application
   (`main`, `lib/`, `res/`, `conf/`, `manifest`), `app/lib/<name>/` for a
   library, `app/cmd/<name>` for a command; then swap it in atomically.
6. Grant the manifest's capabilities and models (`sec/caps/`), as approved at
   install time.

Removing a package removes its layer and, for an application, `data/<name>/`
and `tmp/app/<name>/` (FS_LAYOUT.md §3.6).

## 8. Building with utasm

```sh
utasm -f upk manifest -o calculator.upk \
      --upk-add main=build/main \
      --upk-add res/icon.png=res/icon.png \
      --upk-sign keys/publisher.key
```

`--upk-add PATH=FILE` adds a file under `PATH`; its kind follows from the
path (`main`, `lib/…`, `res/…`, `conf/…`) and from whether it is a UBF.
`--upk-sign KEY` signs with an Ed25519 private key; without it the package is
unsigned.
