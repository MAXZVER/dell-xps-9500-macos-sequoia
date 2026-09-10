# Building AppleALC without Xcode

AppleALC's layout files are compiled into the kext, so anything that changes the DSP graph — such as
[adding a real equaliser to the speaker path](woofers.md#the-speaker-eq-inside-the-driver) — needs a rebuild.
Every guide says that means Xcode.

It does not. **Command Line Tools are enough**, and that matters here: the App Store build of Xcode requires
a newer macOS than Sequoia, and the developer-portal download is 8 GB behind an Apple ID with access. The
whole build takes about a minute.

The script is [`tools/applealc-speaker-eq/build.sh`](../tools/applealc-speaker-eq/build.sh). This page
explains what it does and, more usefully, the four things that go wrong.

## What you need

```bash
xcode-select --install
```

Three sources, all public:

| | |
|---|---|
| [AppleALC](https://github.com/acidanthera/AppleALC) | the plugin itself; built here at `a822e7c` (1.9.7) |
| [Lilu](https://github.com/acidanthera/Lilu) | 1.7.2 — its headers *and* `Library/plugin_start.cpp` |
| [MacKernelSDK](https://github.com/acidanthera/MacKernelSDK) | kernel headers and `libkmod.a` |

No KDK. A KDK is only needed to rebuild *kernel collections*, which is not what this does.

## The four traps

Each one produces a build that looks fine.

### 1. `-DHAVE_ANALOG_AUDIO` — or the layout data silently vanishes

All of AppleALC's codec data sits behind this `#ifdef`. Without it `kern_resources.cpp` compiles without a
single warning to **15 KB instead of 1.88 MB**, and the resulting kext loads, runs, and does nothing at all.

The size of that one object file is the check:

```
kern_resources.o    1879464 bytes      <- correct
kern_resources.o      15xxx bytes      <- the define is missing
```

### 2. `-DPRODUCT_NAME=AppleALC` — or every symbol is named wrong

Lilu's `ADDPR()` macro pastes the product name into every exported symbol. Without the define you get
`_PRODUCT_NAME_kextList` instead of `_AppleALC_kextList`, and the link fails in a way that looks like missing
source files. `-DMODULE_VERSION=1.9.7` is needed for the same reason — Lilu stringifies it.

Also easy to miss: **`Lilu/Library/plugin_start.cpp` must be compiled into your kext.** It is a source file
in Lilu's tree that every plugin includes, not part of Lilu's own binary.

### 3. `ResourceConverter` has to be built first

`ResourceConverter/generate.sh` is what turns `Resources/**/*.xml` into `AppleALC/kern_resources.cpp`. Xcode
runs it as a build phase, and it expects two variables Xcode would have set:

```bash
PROJECT_DIR="$PWD"          # the repository root
TARGET_BUILD_DIR="$RC"      # a directory containing a built ResourceConverter
```

`ResourceConverter` is a separate Objective-C++ helper target — `ResourceConverter/main.mm` — which you build
yourself:

```bash
clang++ -o "$RC/ResourceConverter" ResourceConverter/main.mm -framework Foundation -std=c++17 -O2
```

Miss this and you get worse than an error, because **`generate.sh` deletes `kern_resources.cpp` before
calling the converter.** A run without `TARGET_BUILD_DIR` leaves you with no resource file at all — and since
`kern_resources.cpp` is in `.gitignore`, `git status` shows nothing wrong. It happened here. Re-running with
the converter built restores it.

`generate.sh` also caches by MD5 (`Resources.md5`, `*.xml.md5`) and prints `Trusting existing
kern_resources.cpp` when nothing changed. That is expected, not a failure.

### 4. `kmod_info` — the one that costs you a boot

This is the interesting one. The link succeeds, `file` reports a valid `Mach-O 64-bit kext bundle x86_64`,
every plugin symbol is defined, the undefined symbols all exist in the kernel — and the kernel loads nothing.
No panic, no log line, not a single audio device in the system. `kmutil showloaded | grep AppleALC` is simply
empty.

`kmod_info` is a structure the kernel reads to find a kext's entry points. Xcode generates the file that
defines it, from the `MODULE_NAME`, `MODULE_START` and `MODULE_STOP` build settings. There is no such file in
the repository, so a hand-rolled build has no `kmod_info`, and a kext without it is rejected in silence.

`libkmod.a` does not supply it: the archive holds `c_start.o` and `c_stop.o`, which *reference* `_kmod_info`
but do not define it. And because nothing in your own objects references it either, the linker never pulls
those members in at all.

**The one-line diagnosis**, which takes a second and would have saved a reboot:

```bash
nm your-AppleALC | grep _kmod_info
```

```
00000000001ab5f0 D _kmod_info       <- stock AppleALC
                                    <- ours: nothing
```

The fix is [`tools/applealc-speaker-eq/kmod_glue.c`](../tools/applealc-speaker-eq/kmod_glue.c), which is
exactly what Xcode would have generated:

```c
#include <mach/mach_types.h>

extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);
extern kern_return_t AppleALC_kern_start(kmod_info_t *ki, void *data);
extern kern_return_t AppleALC_kern_stop(kmod_info_t *ki, void *data);

__attribute__((visibility("default")))
KMOD_EXPLICIT_DECL(as.vit9696.AppleALC, "1.9.7", _start, _stop)

__private_extern__ kmod_start_func_t *_realmain = AppleALC_kern_start;
__private_extern__ kmod_stop_func_t  *_antimain = AppleALC_kern_stop;
```

Three things have to line up. The first macro argument must equal `CFBundleIdentifier` and the second
`CFBundleVersion` from the kext's `Info.plist`. `_realmain` / `_antimain` are what `c_start.o` and `c_stop.o`
call, and they point at Lilu's plugin entry points, whose names come from `MODULE_START` / `MODULE_STOP` in
the Xcode project (`$(PRODUCT_NAME)_kern_start`). Referencing `_start` / `_stop` is also what finally makes
the linker pull `libkmod.a` in.

The structure can be read back out of the finished binary — the name occupies 64 bytes at offset 16, the
version the 64 after that — and both must match the bundle:

```
AppleALC (built)   name='as.vit9696.AppleALC' version='1.9.7'
AppleALC (stock)   name='as.vit9696.AppleALC' version='1.9.7'
```

`build.sh` checks for the symbol and refuses to finish without it.

## Validating before you reboot

There is no way to fully link-test a kext on stock macOS. `kextutil` is a shim over `kmutil` in Sequoia:

```
kextutil: -n is not a supported kmutil mode
```

and `kmutil create` refuses without a KDK matching your build:

```
Missing Developer Kit: As of macOS 13.0, you will need to install a KDK matching
your build 24G830 to rebuild kernel collections.
```

What you *can* do, and what caught the real problem, is compare your binary against the stock one
structurally:

```bash
N=out/AppleALC
S=/Volumes/EFI/EFI/OC/Kexts/AppleALC.kext/Contents/MacOS/AppleALC

otool -hv "$N" | tail -1                  # must say KEXTBUNDLE ... NOUNDEFS
nm "$N" | grep _kmod_info                 # must be present  (trap 4)
nm -u "$N" | sort -u > /tmp/n
nm -u "$S" | sort -u > /tmp/s
comm -23 /tmp/n /tmp/s                    # symbols you need that stock does not
```

Anything in that last list has to exist in the kernel, which is directly checkable:

```bash
nm /System/Library/Kernels/kernel | awk '{print $NF}' | sort -u > /tmp/k
grep -qx '__ZN9IOService4initEP12OSDictionary' /tmp/k && echo present
```

This build needed seven symbols the stock one does not — IOKit base-class slots and `IORPC` dispatch, all
present in the kernel. It also exports 49 more symbols than stock, because the visibility flags differ;
harmless, since they are all `AlcEnabler`-mangled names that cannot collide with another kext.

## Installing and reverting

Only the binary changes. Keep the rest of the bundle — in particular `Info.plist`, which is where the
[woofer pin configuration](woofers.md#a-the-pin-config-permanently) lives.

```bash
D=/Volumes/EFI/EFI/OC/Kexts/AppleALC.kext/Contents/MacOS
sudo cp "$D/AppleALC" "$D/AppleALC.stock"        # back up first, always
sudo cp out/AppleALC "$D/AppleALC"
sudo chmod 755 "$D/AppleALC"
```

Have the revert typed out **before** you reboot:

```bash
sudo cp "$D/AppleALC.stock" "$D/AppleALC"
```

The failure mode is losing audio, not losing the machine — this kext is not boot-critical. If you lose SSH
as well you will need the recovery USB, so having one made is the sensible precaution.

After booting:

```bash
kmutil showloaded | grep -i applealc
```

Stock and custom builds are distinguishable by load size (`0x1cd000` against `0x1de000` here) as well as by
file size on the ESP.

## Reproducibility

The build is byte-reproducible apart from the linker-generated `LC_UUID`: rebuilding from scratch and
comparing against the installed binary gave **16 differing bytes**, which is exactly the UUID. A rebuild that
differs by more than that means something in the resource generation changed.

## Note on updates

This replaces a file inside a kext bundle, so an AppleALC update overwrites it. Keep `build.sh` and the
patch, rebuild against the new tag, and re-check `nm | grep _kmod_info` each time.

## It applies to any Lilu plugin

Nothing above is specific to AppleALC beyond the product name and the `HAVE_ANALOG_AUDIO` define. The same
four traps — the plugin's own defines, `plugin_start.cpp`, the generated resources, and `kmod_info` — are all
that stand between Command Line Tools and any Lilu plugin built by hand.
