import sys
import struct

def pad8(n):
    return (n + 7) & ~7

def inject(binary_path, dylib_path):
    with open(binary_path, "r+b") as f:
        magic = f.read(4)
        if magic == b"\xca\xfe\xba\xbe":
            nfat = struct.unpack(">I", f.read(4))[0]
            for i in range(nfat):
                cputype, cpusubtype, offset, size, align = struct.unpack(">IIIII", f.read(20))
                pos = f.tell()
                inject_slice(f, offset, dylib_path)
                f.seek(pos)
        elif magic in (b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe"):
            inject_slice(f, 0, dylib_path)
        else:
            raise ValueError("Unsupported Mach-O magic")

def inject_slice(f, arch_offset, dylib_path):
    f.seek(arch_offset)
    magic = f.read(4)
    cpu, sub, ftype, ncmds, sizeofcmds, flags, reserved = struct.unpack("<IIIIIII", f.read(28))
    
    path_bytes = dylib_path.encode("utf-8") + b"\x00"
    cmdsize = pad8(24 + len(path_bytes))
    
    # Check existing commands
    curr = arch_offset + 32
    for _ in range(ncmds):
        f.seek(curr)
        cmd, csize = struct.unpack("<II", f.read(8))
        if cmd == 0xc: # LC_LOAD_DYLIB
            offset_str = struct.unpack("<I", f.read(4))[0]
            f.seek(curr + offset_str)
            existing_path = f.read(csize - offset_str).split(b"\x00")[0].decode("utf-8")
            if existing_path == dylib_path:
                print(f"Slice at {hex(arch_offset)} already has {dylib_path}")
                return
        curr += csize
            
    insert_pos = arch_offset + 32 + sizeofcmds
    dylib_cmd = struct.pack("<IIIIII", 0xc, cmdsize, 24, 2, 0x10000, 0x10000)
    dylib_cmd += path_bytes
    dylib_cmd += b"\x00" * (cmdsize - len(dylib_cmd))
    
    f.seek(insert_pos)
    f.write(dylib_cmd)
    
    # Update header
    f.seek(arch_offset + 16)
    f.write(struct.pack("<II", ncmds + 1, sizeofcmds + cmdsize))
    print(f"Injected LC_LOAD_DYLIB ({dylib_path}) into slice at {hex(arch_offset)}: ncmds={ncmds+1}, sizeofcmds={sizeofcmds+cmdsize}")

if __name__ == "__main__":
    inject(sys.argv[1], sys.argv[2])
