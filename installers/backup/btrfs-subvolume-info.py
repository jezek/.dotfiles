#!/usr/bin/env python3
"""Read subvolume identity without the privileged tree search used by btrfs show."""

import ctypes
import fcntl
import os
import sys
import uuid


class SubvolumeInfo(ctypes.Structure):
    # Linux UAPI: struct btrfs_ioctl_get_subvol_info_args in linux/btrfs.h.
    _fields_ = [
        ("treeid", ctypes.c_uint64),
        ("name", ctypes.c_char * 256),
        ("parent_id", ctypes.c_uint64),
        ("dirid", ctypes.c_uint64),
        ("generation", ctypes.c_uint64),
        ("flags", ctypes.c_uint64),
        ("uuid", ctypes.c_ubyte * 16),
        ("parent_uuid", ctypes.c_ubyte * 16),
        ("received_uuid", ctypes.c_ubyte * 16),
        ("transids", ctypes.c_uint64 * 4),
        ("times", ctypes.c_uint64 * 8),
        ("reserved", ctypes.c_uint64 * 8),
    ]


def main():
    path, field = sys.argv[1:]
    buffer = bytearray(ctypes.sizeof(SubvolumeInfo))
    # BTRFS_IOC_GET_SUBVOL_INFO = _IOR(0x94, 60, struct ...), generic Linux ABI.
    request = (2 << 30) | (len(buffer) << 16) | (0x94 << 8) | 60
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        fcntl.ioctl(descriptor, request, buffer)
    finally:
        os.close(descriptor)
    info = SubvolumeInfo.from_buffer(buffer)
    if field == "id":
        print(info.treeid)
    elif field in ("uuid", "parent_uuid"):
        value = bytes(getattr(info, field))
        print(str(uuid.UUID(bytes=value)) if any(value) else "-")
    else:
        raise ValueError(f"Unsupported subvolume field: {field}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"Cannot read Btrfs subvolume identity: {error}", file=sys.stderr)
        sys.exit(1)
