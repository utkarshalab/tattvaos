"""Scalable canonical ref catalog and mutable-root tests."""
import ctypes
import hashlib
import struct
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
OK, CORRUPT = 0, 5


class RefRoot(ctypes.Structure):
    _fields_ = [("records", P), ("record_bytes", ctypes.c_uint64),
                ("generation", ctypes.c_uint64), ("root_hash", P)]


lib.vcs_ref_catalog_validate.argtypes = [P, ctypes.c_uint64]
lib.vcs_ref_catalog_validate.restype = ctypes.c_uint64
lib.vcs_ref_key_hash.argtypes = [P, P]
lib.vcs_ref_key_hash.restype = ctypes.c_uint64
lib.vcs_ref_root_hash.argtypes = [ctypes.POINTER(RefRoot)]
lib.vcs_ref_root_hash.restype = ctypes.c_uint64
lib.vcs_ref_root_verify.argtypes = [ctypes.POINTER(RefRoot)]
lib.vcs_ref_root_verify.restype = ctypes.c_uint64


def array(data):
    return (ctypes.c_ubyte * max(1, len(data)))(*data)


def record(kind, name, generation, target, flags=0):
    encoded = name.encode("ascii")
    padding = (-len(encoded)) & 7
    return (struct.pack("<BBHIQ", kind, len(encoded), flags, 0, generation)
            + target + encoded + bytes(padding))


targets = [hashlib.sha256(b"ref-target-" + bytes([index])).digest()
           for index in range(5)]
main_record = record(1, "main", 7, targets[0], 1)
main_key = hashlib.sha256(b"UVCSRFK1" + struct.pack("<HBB", 1, 1, 4)
                          + b"main").digest()
records = [main_record,
           record(1, "release/v3", 2, targets[1]),
           record(2, "v3.0", 1, targets[2]),
           record(3, "origin/main", 4, targets[3]),
           record(4, "HEAD", 9, main_key, 2)]
catalog_bytes = b"".join(records)
catalog = array(catalog_bytes)
assert lib.vcs_ref_catalog_validate(catalog, len(catalog_bytes)) == OK
key_output = (ctypes.c_ubyte * 32)()
main_buffer = array(main_record)
assert lib.vcs_ref_key_hash(main_buffer, key_output) == OK
assert bytes(key_output) == main_key

root_hash = (ctypes.c_ubyte * 32)()
root = RefRoot(catalog, len(catalog_bytes), 31, root_hash)
assert lib.vcs_ref_root_hash(ctypes.byref(root)) == OK
frame = b"UVCSROT1" + struct.pack("<HHIQQ", 1, 1, 0, 31,
                                   len(catalog_bytes))
assert bytes(root_hash) == hashlib.sha256(frame + catalog_bytes).digest()
assert lib.vcs_ref_root_verify(ctypes.byref(root)) == OK
root_hash[0] ^= 1
assert lib.vcs_ref_root_verify(ctypes.byref(root)) == CORRUPT
root_hash[0] ^= 1

# Empty generations have a canonical hash too.
empty_hash = (ctypes.c_ubyte * 32)()
empty = RefRoot(None, 0, 1, empty_hash)
assert lib.vcs_ref_root_hash(ctypes.byref(empty)) == OK
empty_frame = b"UVCSROT1" + struct.pack("<HHIQQ", 1, 1, 0, 1, 0)
assert bytes(empty_hash) == hashlib.sha256(empty_frame).digest()

# Ordering, header, name, target and padding corruption fail closed.
reversed_catalog = array(records[1] + records[0])
assert lib.vcs_ref_catalog_validate(reversed_catalog,
                                    len(records[1] + records[0])) == CORRUPT
for bad_name in ("", ".hidden", "a//b", "a/.vcs", "a.vcs", "a/", "bad name"):
    malformed = array(record(1, bad_name, 1, targets[0]))
    assert lib.vcs_ref_catalog_validate(malformed, len(malformed)) == CORRUPT
symbolic_tag = array(record(2, "alias", 1, main_key, 2))
assert lib.vcs_ref_catalog_validate(symbolic_tag, len(symbolic_tag)) == CORRUPT
for offset in (0, 2, 4, 8, 16):
    malformed_bytes = bytearray(records[0])
    if offset == 0:
        malformed_bytes[offset] = 5
    elif offset == 2:
        malformed_bytes[offset] = 4
    elif offset == 4:
        malformed_bytes[offset] = 1
    elif offset == 8:
        malformed_bytes[offset:offset + 8] = bytes(8)
    else:
        malformed_bytes[offset:offset + 32] = bytes(32)
    malformed = array(malformed_bytes)
    assert lib.vcs_ref_catalog_validate(malformed, len(malformed_bytes)) == CORRUPT
padding_bad = bytearray(record(1, "abc", 1, targets[0]))
padding_bad[-1] = 1
padding_buffer = array(padding_bad)
assert lib.vcs_ref_catalog_validate(padding_buffer, len(padding_bad)) == CORRUPT

print("VCS ref catalog: PASS (variable records, names, ordering, root/key hashes, corruption)")
