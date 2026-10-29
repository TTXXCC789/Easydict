#!/usr/bin/env python3
"""Add an LC_LOAD_DYLIB only when every Mach-O slice has verified free space.

Derived from the fork's original injector; this edition bounds every read and
validates all slices before writing. Supports little-endian Mach-O 64-bit and
big-endian universal headers. Existing matching load commands are left alone.
"""

import argparse
import os
from pathlib import Path
import struct
import tempfile


def unpack(data, fmt, offset, end):
    size = struct.calcsize(fmt)
    if offset < 0 or offset + size > end or end > len(data):
        raise ValueError("Truncated or out-of-bounds Mach-O structure")
    return struct.unpack_from(fmt, data, offset)


def slices(data):
    magic = bytes(data[:4])
    if magic == b"\xcf\xfa\xed\xfe":
        return [(0, len(data))]
    if magic not in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
        raise ValueError("Expected a little-endian 64-bit Mach-O or universal binary")
    count, = unpack(data, ">I", 4, len(data))
    fmt = ">IIQQII" if magic[-1] == 0xBF else ">IIIII"
    size = struct.calcsize(fmt)
    table_end = 8 + count * size
    if count == 0 or count > 64 or table_end > len(data):
        raise ValueError("Invalid universal architecture table")
    result = []
    for index in range(count):
        entry = unpack(data, fmt, 8 + index * size, table_end)
        offset, length = entry[2:4]
        if offset < table_end or length < 32 or offset + length > len(data):
            raise ValueError("Invalid universal slice bounds")
        result.append((offset, length))
    ordered = sorted(result)
    if any(a + n > b for (a, n), (b, _) in zip(ordered, ordered[1:])):
        raise ValueError("Overlapping universal slices")
    return result


def plan_slice(data, start, length, library):
    end = start + length
    if bytes(data[start:start + 4]) != b"\xcf\xfa\xed\xfe":
        raise ValueError("Unsupported slice: only little-endian Mach-O 64-bit is supported")
    header = unpack(data, "<8I", start, end)
    count, command_bytes = header[4:6]
    command_end = start + 32 + command_bytes
    if command_end > end or count > command_bytes // 8:
        raise ValueError("Invalid Mach-O load-command bounds")
    current = start + 32
    first_section = end
    found = False
    for _ in range(count):
        command, size = unpack(data, "<II", current, command_end)
        if size < 8 or size % 8 or current + size > command_end:
            raise ValueError("Invalid load-command size")
        if command == 0xC:  # LC_LOAD_DYLIB
            if size < 24:
                raise ValueError("Truncated dylib command")
            name_offset, = unpack(data, "<I", current + 8, current + size)
            if not 24 <= name_offset < size:
                raise ValueError("Invalid dylib name offset")
            raw = bytes(data[current + name_offset:current + size])
            if b"\0" not in raw:
                raise ValueError("Unterminated dylib name")
            found |= raw.split(b"\0", 1)[0] == library.encode("utf-8")
        if command == 0x19:  # LC_SEGMENT_64
            if size < 72:
                raise ValueError("Truncated segment command")
            section_count, = unpack(data, "<I", current + 64, current + size)
            if 72 + section_count * 80 > size:
                raise ValueError("Truncated section table")
            for index in range(section_count):
                section = current + 72 + index * 80
                file_offset, = unpack(data, "<I", section + 48, current + size)
                flags, = unpack(data, "<I", section + 64, current + size)
                # Zerofill sections occupy virtual memory only.
                if flags & 0xFF not in (0x1, 0xC, 0x12) and file_offset:
                    if file_offset >= length:
                        raise ValueError("Invalid file-backed section offset")
                    first_section = min(first_section, start + file_offset)
        current += size
    if current != command_end:
        raise ValueError("Load-command byte count does not match header")
    if found:
        return None
    name = library.encode("utf-8") + b"\0"
    new_size = (24 + len(name) + 7) & ~7
    if first_section == end or command_end + new_size > first_section:
        raise ValueError("Insufficient verified header padding; use a source build instead")
    if any(data[command_end:command_end + new_size]):
        raise ValueError("Header padding is not empty; refusing to overwrite bytes")
    addition = struct.pack("<6I", 0xC, new_size, 24, 2, 0x10000, 0x10000)
    addition += name + b"\0" * (new_size - 24 - len(name))
    return command_end, addition, start + 16, struct.pack("<II", count + 1, command_bytes + new_size)


def patched_bytes(data, library):
    if not library or "\0" in library:
        raise ValueError("Invalid library path")
    plans = [plan_slice(data, start, length, library) for start, length in slices(data)]
    result = bytearray(data)
    for plan in plans:
        if plan:
            offset, addition, header_offset, header = plan
            result[offset:offset + len(addition)] = addition
            result[header_offset:header_offset + len(header)] = header
    return bytes(result), sum(plan is not None for plan in plans)


def inject(path, library, check=False):
    path = Path(path)
    content, changed = patched_bytes(path.read_bytes(), library)
    if changed and not check:
        descriptor, temporary = tempfile.mkstemp(dir=str(path.parent), prefix=".macho-")
        try:
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(content)
            os.chmod(temporary, path.stat().st_mode & 0o777)
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    return changed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("library")
    parser.add_argument("--check", action="store_true", help="Validate without changing the file")
    args = parser.parse_args()
    try:
        changed = inject(args.binary, args.library, args.check)
        print("%d slice(s) %s" % (changed, "need injection" if args.check else "injected"))
    except (OSError, ValueError) as error:
        parser.exit(1, "Injection refused: %s\n" % error)
