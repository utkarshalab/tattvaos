# Working persistent UXFS volume

Ush uses `volume.asm`, a bounded UXFS **v2** implementation, rather than the
legacy `vfs/vfs.asm` entry points. Those older entry points still contain
success-only read/write and mount scaffolding and are not qualified for storage.
The v2 disk format is deliberately distinct from the legacy v1 declarations;
there is no existing-image migration or compatibility claim.

The implementation and its sector backends are NASM. Python explicitly formats
new images and drives tests; it does not service guest filesystem operations.

## Use

From the repository root in Linux/WSL:

```sh
make -C apps/ush
python3 storage/uxfs/mkvolume.py apps/ush/build/data.uxfs
apps/ush/build/ush --disk apps/ush/build/data.uxfs
```

The formatter uses exclusive creation and refuses to overwrite existing files.
The shell never automatically formats disks. Its Linux backend opens only the
explicit image, requires a regular file of sufficient size, refuses symlinks,
and obtains an exclusive nonblocking lock. Relative shell paths refer to the
UXFS volume, never to the host filesystem.

For the native BIOS kernel, attach that image as **secondary IDE master**:

```sh
make -C boot run UXFS_IMAGE=../apps/ush/build/data.uxfs
```

The native backend accesses only ports 0x170/0x376. It checks IDENTIFY capacity,
uses bounded polling, transfers every sector, checks completion errors, and
issues FLUSH CACHE. It does not select or write the primary boot disk. This is
a QEMU IDE backend, not an AHCI/NVMe or physical hardware qualification. OVMF/q35
tests attach an explicit `piix3-ide` controller for this backend.

```text
mkdir /notes
cd /notes
touch empty
write hello "Hello from Utkarsha"
cp hello copy
mv copy renamed
ls
cat renamed
```

Additional commands are `rm FILE`, `rmdir DIR`, `append FILE TEXT`, `stat PATH`,
`df`, `du [PATH]`, `head`, `tail`, `wc`, `grep`, `find`, and `hexdump`. Deletion
reclaims a zeroed record; empty-directory removal refuses root/current directory.
Power commands use `uxv_sync` to flush before the kernel power hook and cancel
on flush error. Logical deletion does not erase data retained in the other bank.

Commands are `pwd`, `ls [DIR]`, `cd [DIR]` (defaults to current directory),
`cat FILE`, `touch FILE`, `mkdir DIR`, `write FILE TEXT`, `cp SOURCE DEST`, and
`mv SOURCE DEST`. `touch` preserves existing contents; timestamps are not yet
represented. `write` replaces contents and creates a missing file. `cp` handles
regular files; `mv` also renames directory subtrees and updates the working
directory. Both refuse existing destinations, including the same file. Neither
implicitly appends a basename when the destination names a directory.

Paths support absolute/relative names, repeated slashes, `.` and `..`. Each
traversed prefix must exist as a directory, including prefixes before `..`.
Missing parents, invalid types, overlong paths, capacity exhaustion and move
cycles fail without changing the volume. Directory moves preflight every
descendant path length and collision before changing any metadata.

## Bounds and disk format

This implementation holds 64 records including root, with up to 4096 data bytes
per regular file and 239 bytes per absolute path. Directories share the record
budget. It has no symlinks, hard links, permissions, timestamps,
recursive copy, mounts, or growing extents. No claim is made that all UXFS
features in older headers are implemented. The runtime is a single serialized
BSP owner; no other thread or guest may write this volume concurrently.

An image is 558080 bytes: two banks of 545 sectors (512 bytes per sector).
Each bank has one header sector and 64 records of 4352 bytes. A record holds a
240-byte NUL-terminated absolute path, u64 type (0 unused, 1 file, 2 directory),
u64 byte size, and 4096 bytes of content. Slot zero is the root directory.
All integers are little endian.

The header has u64 magic `0x32564c4f56584655`, version 2, nonzero generation,
FNV-1a-64 payload checksum, and FNV-1a-64 header checksum at offsets 0,8,16,24,32.
The header checksum is computed over all 512 bytes with its own field zeroed.
FNV checks accidental corruption; it is not authentication or a security hash.
Mount validates checksums, sizes, record types, canonical paths, unique names,
and directory ancestry, then selects the highest complete valid generation.

A mutation writes the inactive payload, flushes, writes its new header, then
flushes again. The active bank is never modified by that transaction. No success
is returned until both flushes complete. An I/O failure disables the current
mount, preventing exposure of uncommitted RAM state. A failed final write/flush
can already have committed: reboot recovery may select either complete old or
complete new state. There is no false rollback guarantee. The model assumes
the backend honors sector writes and flush ordering; it does not guarantee
recovery from damage to both banks or dishonest storage hardware.

## Checks

```sh
make -C apps/ush test
python3 boot/tests/test_ush_qemu.py --firmware bios --storage-test
python3 boot/tests/test_ush_qemu.py --firmware ovmf --storage-test
```

Host tests run the real NASM engine, remount across independent shell processes,
check errors leave disk bytes unchanged, exhaust the record budget, corrupt a
snapshot, and inject partial body/header writes and flush failures. QEMU storage
tests create an isolated image, write/copy/move files and a directory subtree,
terminate that guest, then start a second guest on the same image and verify
contents. The usual editor, calculator, scheduler-yield and exit checks also run.
