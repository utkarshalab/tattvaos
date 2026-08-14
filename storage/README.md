# storage — Storage Subsystem Category

> Storage subsystem category for Tattva OS.
> Filesystem, database, object storage, and NVMe access.

---

## Projects

| Project | Description | Master Location |
|---|---|---|
| **uxfs** | Tattva filesystem — custom, log-structured, NVMe-optimized | [`uxfs/`](uxfs/) |
| **uwal** | Write-ahead log — durability substrate for udb and friends | [`uwal/`](uwal/) |
| **udb** | Sagar — embedded database, B-tree + LSM, purpose-built | [`udb/`](udb/) |
| **uobject** | Sangraha — object storage, S3-compatible API | [`uobject/`](uobject/) |
| **ubxp** | UBXP — tagged binary serialization for storage and network | [`ubxp/`](ubxp/) |

---

## Architecture

No VFS overhead. No redundant block layers. Direct hardware queue submission.
The filesystem is a first-class citizen of the Tattva OS unikernel architecture.
