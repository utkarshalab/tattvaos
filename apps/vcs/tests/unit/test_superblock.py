"""Exact format-v3 repository superblock sealing and verification tests."""
import ctypes
import hashlib
import struct
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
OK, CORRUPT = 0, 5
lib.vcs_superblock_seal.argtypes = [P]
lib.vcs_superblock_seal.restype = ctypes.c_uint64
lib.vcs_superblock_verify.argtypes = [P]
lib.vcs_superblock_verify.restype = ctypes.c_uint64


def valid_image(features=3):
    image = bytearray(512)
    image[:8] = b"UVCSREP3"
    struct.pack_into("<IIQQ", image, 8, 3, 512, features, 27)
    image[32:48] = bytes.fromhex("00112233445566778899aabbccddeeff")
    struct.pack_into("<II", image, 48, 1, 4096)
    image[56:88] = hashlib.sha256(b"head commit").digest()
    image[88:120] = hashlib.sha256(b"ref catalog").digest()
    image[120:152] = hashlib.sha256(b"ownership catalog").digest()
    image[184:216] = hashlib.sha256(b"object index").digest()
    struct.pack_into("<QQq", image, 248, 91, 103, 0)
    return image


image = valid_image()
buffer = (ctypes.c_ubyte * 512).from_buffer(image)
assert lib.vcs_superblock_seal(buffer) == OK
assert bytes(image[480:]) == hashlib.sha256(image[:480]).digest()
assert lib.vcs_superblock_verify(buffer) == OK

with_operation = valid_image(0x0B)
with_operation[152:184] = hashlib.sha256(b"operation head").digest()
operation_buffer = (ctypes.c_ubyte * 512).from_buffer(with_operation)
assert lib.vcs_superblock_seal(operation_buffer) == OK
assert lib.vcs_superblock_verify(operation_buffer) == OK

mutations = [
    (0, b"X"), (8, struct.pack("<I", 2)), (12, struct.pack("<I", 511)),
    (16, struct.pack("<Q", 1)), (16, struct.pack("<Q", 0x13)),
    (24, bytes(8)), (32, bytes(16)), (48, struct.pack("<I", 2)),
    (52, struct.pack("<I", 8192)), (88, bytes(32)), (120, bytes(32)),
    (184, bytes(32)), (256, bytes(8)), (272, b"\x01"),
]
for offset, replacement in mutations:
    bad = valid_image()
    bad[480:] = b"\xA5" * 32
    bad[offset:offset + len(replacement)] = replacement
    before = bytes(bad[480:])
    bad_buffer = (ctypes.c_ubyte * 512).from_buffer(bad)
    assert lib.vcs_superblock_seal(bad_buffer) == CORRUPT
    assert bytes(bad[480:]) == before

bad_operation = valid_image(3)
bad_operation[152:184] = hashlib.sha256(b"unexpected operation").digest()
assert lib.vcs_superblock_seal((ctypes.c_ubyte * 512).from_buffer(bad_operation)) == CORRUPT

tampered = bytearray(image)
tampered[57] ^= 1
assert lib.vcs_superblock_verify((ctypes.c_ubyte * 512).from_buffer(tampered)) == CORRUPT
tampered = bytearray(image)
tampered[500] ^= 1
assert lib.vcs_superblock_verify((ctypes.c_ubyte * 512).from_buffer(tampered)) == CORRUPT

print("VCS superblock: PASS (exact layout, feature/root validation, seal, checksum, tamper rejection)")
