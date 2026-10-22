#!/bin/sh
#
#  make_fixtures.sh
#  BinaryInspectorTests
#
#  Rebuilds the Mach-O fixtures in MachO/ from the C sources in src/. Run it from anywhere on a
#  Mac with the developer tools; the tests assert values read from these exact files with otool
#  and nm, so after rebuilding, re-read them and update MachOParserTests.
#
#  Created by David Sherlock on 10/22/26.
#  Copyright © 2026 ArrayPress Limited. MIT licence.
#
#  Builds in a temporary directory and maps its path away (-fdebug-prefix-map for the source
#  stabs, -oso_prefix for the object-file stabs) so no local path ends up in a fixture.
#  ZERO_AR_DATE=1 zeroes the object timestamps the linker records.

set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="$here/MachO"
work=$(mktemp -d)
work=$(cd "$work" && pwd -P)
trap 'rm -rf "$work"' EXIT
cp "$here"/src/*.c "$work"/
cd "$work"
export ZERO_AR_DATE=1
map="-fdebug-prefix-map=$work=/fixtures"

# hello: arm64 (LC_BUILD_VERSION, ad-hoc signed by the linker) and x86_64 (old deployment
# target, so LC_VERSION_MIN_MACOSX; the linker does not sign x86_64), both with debug stabs.
clang -g -Os $map -arch arm64 -mmacosx-version-min=12.0 -c hello.c -o hello-arm64.o
clang -arch arm64 -mmacosx-version-min=12.0 hello-arm64.o -o hello-arm64 -Wl,-oso_prefix,"$work/"
clang -g -Os $map -arch x86_64 -mmacosx-version-min=10.13 -c hello.c -o hello-x86_64.o
clang -arch x86_64 -mmacosx-version-min=10.13 hello-x86_64.o -o hello-x86_64 -Wl,-oso_prefix,"$work/"
lipo -create hello-x86_64 hello-arm64 -output hello-universal
lipo -create -fat64 hello-x86_64 hello-arm64 -output hello-universal-fat64

# libgreeter.dylib: install name, versions, an rpath, and weak / re-export / upward links.
clang -Os -arch arm64 -mmacosx-version-min=12.0 -dynamiclib greeter.c -o libgreeter.dylib \
    -install_name @rpath/libgreeter.dylib -current_version 2.3.4 -compatibility_version 2.0 \
    -Wl,-rpath,@loader_path/../lib -Wl,-weak-lz -Wl,-reexport-lc++ -Wl,-upward-lobjc

# plugin.bundle: MH_BUNDLE.
clang -Os -arch arm64 -mmacosx-version-min=12.0 -bundle plugin.c -o plugin.bundle

# plugin.o: MH_OBJECT, one unnamed segment, no LC_MAIN or signature.
clang -Os -arch arm64 -mmacosx-version-min=12.0 -c plugin.c -o plugin.o

# 32-bit images: hello for watchOS arm64_32 (a LINKED 32-bit executable: MH_MAGIC, LC_SEGMENT and
# 32-bit nlist), and i386 / armv7 objects (current linkers refuse to link either, but clang still
# compiles them).
xcrun --sdk watchos clang -Os -arch arm64_32 -mwatchos-version-min=8.0 hello.c -o hello-arm64_32
clang -Os -arch i386 -mmacosx-version-min=10.13 -c plugin.c -o plugin-i386.o
clang -Os -target armv7-apple-ios10.0 -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" -c plugin.c -o plugin-armv7.o

# Encryption: an iOS executable linked -encryptable carries LC_ENCRYPTION_INFO_64 with cryptid 0.
# hello-ios-encrypted is the same file with cryptid set to 1, as FairPlay leaves an App Store
# binary (only Apple's servers encrypt; its code signature no longer matches, which is fine here).
xcrun --sdk iphoneos clang -Os -arch arm64 -miphoneos-version-min=15.0 hello.c -o hello-ios -Wl,-encryptable
python3 - hello-ios hello-ios-encrypted <<'PY'
import struct, sys
data = bytearray(open(sys.argv[1], "rb").read())
ncmds = struct.unpack_from("<I", data, 16)[0]
offset = 32  # mach_header_64
for _ in range(ncmds):
    cmd, size = struct.unpack_from("<II", data, offset)
    if cmd == 0x2C:  # LC_ENCRYPTION_INFO_64: cryptoff, cryptsize, cryptid
        struct.pack_into("<I", data, offset + 16, 1)
        break
    offset += size
else:
    sys.exit("no LC_ENCRYPTION_INFO_64")
open(sys.argv[2], "wb").write(data)
PY

cp hello-arm64 hello-x86_64 hello-universal hello-universal-fat64 libgreeter.dylib plugin.bundle plugin.o \
    hello-arm64_32 plugin-i386.o plugin-armv7.o hello-ios hello-ios-encrypted "$out"/
ls -l "$out"
