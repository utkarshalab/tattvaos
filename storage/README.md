# storage — Storage Subsystem Category

> Storage subsystem category for Tattva OS.
> Filesystem, database, object storage, and NVMe access.

---

## Projects

| Project | Description | Master Location |
|---|---|---|
| **ufs** | Tattva filesystem — custom, log-structured, NVMe-optimized | [`ufs/`](ufs/) |
| **udb** | Sagar — embedded database, B-tree + LSM, purpose-built | [`udb/`](udb/) |
| **uobject** | Sangraha — object storage, S3-compatible API | [`uobject/`](uobject/) |
| **ubxp** | BXP binary format — serialization for storage and network | [`ubxp/`](ubxp/) |

---

## Architecture

No VFS overhead. No redundant block layers. Direct hardware queue submission.
The filesystem is a first-class citizen of the Tattva OS unikernel architecture.
