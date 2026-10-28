#!/usr/bin/env python3
"""Explicitly create a NEW bounded UXFS v2 image; never overwrite a file."""
import argparse
import os
from pathlib import Path
import struct

NODES, NODE, BANK = 64, 4352, 545
MAGIC = 0x32564c4f56584655

def checksum(data):
    value = 0xcbf29ce484222325
    for byte in data:
        value = ((value ^ byte) * 0x100000001b3) & ((1 << 64) - 1)
    return value

def image():
    body = bytearray(NODES * NODE)
    body[:2] = b'/\0'
    struct.pack_into('<Q', body, 240, 2)
    header = bytearray(512)
    struct.pack_into('<4Q', header, 0, MAGIC, 2, 1, checksum(body))
    struct.pack_into('<Q', header, 32, checksum(header))
    return header + body + bytes(BANK * 512)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path', type=Path)
    args = parser.parse_args()
    with args.path.open('xb') as stream:
        stream.write(image())
        stream.flush()
        os.fsync(stream.fileno())
    print(f'Created UXFS v2: {args.path} ({BANK * 1024} bytes)')

if __name__ == '__main__':
    main()
