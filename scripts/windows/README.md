# Windows local builds

These scripts preserve the local build and packaging workflow without requiring a
particular user profile or checkout directory. Run them in a Visual Studio 2022
x64 Developer PowerShell with the toolchains on `PATH`.

## Prerequisites

- Rust 1.75.0, Visual Studio 2022 C++ Build Tools, Windows SDK and LLVM 15.0.6.
- Flutter 3.24.5 for Windows x64. Set `FLUTTER_ROOT` to that SDK.
- The vcpkg revision and native dependency setup from
  [the build workflow](../../.github/workflows/flutter-build.yml). Set
  `VCPKG_ROOT` and `LIBCLANG_PATH`. The software-codec build needs static x64
  aom, libjpeg-turbo, libvpx, libyuv and opus libraries.
- Python with the packages in `libs/portable/requirements.txt` installed.
- Initialize submodules with `git submodule update --init --recursive`.

Use the workflow's custom Windows engine from
<https://github.com/rustdesk/engine/releases/download/main/windows-x64-release.zip>
in `FLUTTER_ROOT/bin/cache/artifacts/engine/windows-x64-release`, and apply
`.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff` to the SDK.

Restore the `bridge-artifact` ZIP produced by CI for the matching Rust/Flutter
interface into the repository root. The required files are `src/bridge_generated.rs`,
`src/bridge_generated.io.rs`, `flutter/lib/generated_bridge.dart` and
`flutter/lib/generated_bridge.freezed.dart`. Do not run bridge code generation
locally. For the office.1 application source, the upstream baseline is
`fc9713c1b8ed78e780f7b1d35c63e80a05c5bdd9`; the initial verified build used its
[successful CI run](https://github.com/rustdesk/rustdesk/actions/runs/43559822946).
Artifacts can expire; keep a local copy or use a matching CI-generated artifact.

## Flutter Release and portable packages

```powershell
.\scripts\windows\Build-Flutter-Release.ps1 -Python C:\tools\package-venv\Scripts\python.exe
```

Use `-EnvironmentScript C:\tools\build-env.ps1` to load an existing local environment
script. This file is optional and is not distributed with the application.
Use `-OutputDirectory C:\build\packages` to choose a fresh output directory.
The default is `target/windows-packages`. Existing bundle directories are rejected
to prevent stale DLLs from being included.

For a long checkout path, supply `-ShortSourcePath C:\src\codo` to create/use a
directory junction. Use a new path that refers to this checkout. CMake caches its
source path, so rebuild generated Windows build files when switching between
checkout paths. The script uses plugin directory junctions if Windows symbolic
link privileges are unavailable; it does not change Developer Mode settings.

The script builds the Rust Flutter core, virtual-display helper and Flutter
Windows runner, then produces a folder bundle, a ZIP, a single-file portable EXE
and SHA256SUMS.txt. Runtime DLLs, assets, licenses and source metadata are bundled.
`-PackageOnly` packages existing Release outputs without rebuilding the application.
The official portable packer is still built in that mode; `cargo` and Python with
`brotli` must be available. Set `FLUTTER_ROOT` to include the engine license.

The script enables software codecs, matching the verified local build; it does
not enable optional `hwcodec` or `vram` features or install driver packages.

## Sciter debug client

```powershell
.\scripts\windows\Build-CodoRustDesk.ps1 -SciterLibrary C:\tools\sciter.dll
.\scripts\windows\Run-CodoRustDesk.cmd
```

This preserves the README's legacy debug workflow. The Sciter SDK download is
linked from the root README. Use the Flutter build for Google/GitHub login;
the Sciter account dialog only supports username/password authentication.
