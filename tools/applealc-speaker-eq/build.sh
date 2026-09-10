#!/bin/bash
#
# Build AppleALC with a 32-band equaliser on the internal-speaker path.
# Runs on a stock macOS with Command Line Tools only -- Xcode is NOT required.
#
# Produces ./out/AppleALC (a kext binary) to drop into
# EFI/OC/Kexts/AppleALC.kext/Contents/MacOS/AppleALC
#
# Tested on macOS Sequoia 15.7.9 (24G830), Dell XPS 15 9500, ALC289 layout 13.
#
set -eu

ALC_REF=${ALC_REF:-a822e7c}          # AppleALC 1.9.7
LILU_VER=${LILU_VER:-1.7.2}
WORK=${WORK:-$HOME/build}
PATCH=$(cd "$(dirname "$0")" && pwd)/layout13-speaker-eq.patch
GLUE=$(cd "$(dirname "$0")" && pwd)/kmod_glue.c
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk

[ -d "$SDK" ] || { echo "Command Line Tools not installed: xcode-select --install"; exit 1; }
mkdir -p "$WORK"

# ---------------------------------------------------------------- 1. sources
cd "$WORK"
[ -d AppleALC ]     || git clone --quiet https://github.com/acidanthera/AppleALC.git
[ -d MacKernelSDK ] || git clone --quiet https://github.com/acidanthera/MacKernelSDK.git
if [ ! -d Lilu-src ]; then
  curl -sLo lilu.zip "https://github.com/acidanthera/Lilu/archive/refs/tags/$LILU_VER.zip"
  unzip -q lilu.zip && mv "Lilu-$LILU_VER" Lilu-src
fi
cd AppleALC && git checkout --quiet "$ALC_REF"

# ------------------------------------------------- 2. patch the speaker chain
# Inserts DspEqualization32 (instance 0) ahead of DspCrossover2Way (instance 1)
# in the IntSpeaker path of Resources/ALC289/layout13.xml.
git apply --check "$PATCH" 2>/dev/null && git apply "$PATCH" && echo "layout13.xml patched" \
  || echo "layout13.xml already patched (or the patch does not apply -- check by hand)"

# ------------------------------------- 3. regenerate the compiled resource file
# Layout XML is compiled into kern_resources.cpp; this is the step Xcode
# normally runs as a build phase. Two things it expects from Xcode:
#   PROJECT_DIR       -- the repository root
#   TARGET_BUILD_DIR  -- a directory holding a built ResourceConverter, which is
#                        a separate Objective-C++ helper target. Build it first;
#                        generate.sh deletes kern_resources.cpp before calling it,
#                        so a missing converter leaves you with no resources at all.
RC="$WORK/rc"; mkdir -p "$RC"
clang++ -o "$RC/ResourceConverter" ResourceConverter/main.mm   -framework Foundation -std=c++17 -O2 -Wno-deprecated-declarations
PROJECT_DIR="$PWD" TARGET_BUILD_DIR="$RC" bash ./ResourceConverter/generate.sh >/dev/null
echo "kern_resources.cpp regenerated ($(stat -f%z AppleALC/kern_resources.cpp) bytes)"

# --------------------------------------------------------------- 4. compile
OBJ="$WORK/obj"; mkdir -p "$OBJ"
CXXFLAGS=(
  -isysroot "$SDK"
  -I"$WORK/MacKernelSDK/Headers" -I"$WORK/Lilu-src/Lilu" -I"$WORK/Lilu-src"
  -IAppleALC -IAppleALC/ALCUserClientProvider -IAppleALC/ALCUserClient
  -mkernel -fapple-kext
  -fno-builtin -fno-common -fno-exceptions -fno-rtti
  -nostdinc++ -std=c++17 -arch x86_64 -O2
  -DKERNEL -DKERNEL_PRIVATE -DAPPLE -D__MACHO__
  # These three are supplied by the Xcode project and are easy to miss:
  #   PRODUCT_NAME     -- names every exported symbol (ADDPR macro)
  #   HAVE_ANALOG_AUDIO -- without it kern_resources.cpp compiles to a 15 KB stub
  #   MODULE_VERSION   -- the version Lilu reports
  -DPRODUCT_NAME=AppleALC -DHAVE_ANALOG_AUDIO -DMODULE_VERSION=1.9.7
)
SRCS=(
  "$WORK/Lilu-src/Lilu/Library/plugin_start.cpp"
  AppleALC/kern_start.cpp
  AppleALC/kern_alc.cpp
  AppleALC/ALCUserClient/ALCUserClient.cpp
  AppleALC/ALCUserClientProvider/ALCUserClientProvider.cpp
  AppleALC/kern_resources.cpp
)
for f in "${SRCS[@]}"; do
  n=$(basename "$f" .cpp)
  printf '  %-24s ' "$n"
  clang++ -c -o "$OBJ/$n.o" "$f" "${CXXFLAGS[@]}"
  echo "$(stat -f%z "$OBJ/$n.o") bytes"
done

# kmod_info: Xcode generates this file from MODULE_NAME/START/STOP. Without it
# the kext links cleanly and is then silently rejected by the kernel.
printf '  %-24s ' kmod_glue
clang -c -o "$OBJ/kmod_glue.o" "$GLUE" \
  -isysroot "$SDK" -I"$WORK/MacKernelSDK/Headers" \
  -mkernel -fno-builtin -fno-common -arch x86_64 -O2 \
  -DKERNEL -DKERNEL_PRIVATE -DAPPLE -D__MACHO__
echo "$(stat -f%z "$OBJ/kmod_glue.o") bytes"

# ------------------------------------------------------------------ 5. link
OUT="$(cd "$(dirname "$0")" && pwd)/out"; mkdir -p "$OUT"
clang++ -o "$OUT/AppleALC" \
  "$OBJ"/plugin_start.o "$OBJ"/kern_start.o "$OBJ"/kern_alc.o \
  "$OBJ"/ALCUserClient.o "$OBJ"/ALCUserClientProvider.o \
  "$OBJ"/kern_resources.o "$OBJ"/kmod_glue.o \
  -isysroot "$SDK" -arch x86_64 -mkernel -nostdlib -fapple-kext \
  -L"$WORK/MacKernelSDK/Library/x86_64" -lkmod -Xlinker -kext

# ------------------------------------------------------------- 6. sanity check
echo
file "$OUT/AppleALC"
if nm "$OUT/AppleALC" | grep -q ' D _kmod_info'; then
  echo "kmod_info: present  -- the kernel will accept this kext"
else
  echo "kmod_info: MISSING  -- the kernel would reject this silently. Do not install."
  exit 1
fi
echo "undefined symbols: $(nm -u "$OUT/AppleALC" | wc -l | tr -d ' ') (resolved at load time)"
echo
echo "Built: $OUT/AppleALC"
