# Garmin Connect IQ Apps

Monkey C apps for Garmin Connect IQ, targeting **fēnix 8** and **Edge 850**
(both Connect IQ API Level 6.0).

## Environment

| Component | Choice | Why |
|---|---|---|
| OS | Windows 11 native | The toolchain is not POSIX-native — `monkeyc` is a Java-based compiler with no make/gcc step. WSL would add WSLg overhead for the simulator, `usbipd-win` for USB device access, and slow `/mnt/f` I/O with nothing gained. Linux is supported but fights old GTK/webkit dependencies and ships the simulator as an AppImage workaround. |
| Editor | VS Code + `garmin.monkey-c` | The only first-party integration: LSP, step debugger, simulator, profiler, `.iq` export. |
| JDK | Temurin 21 LTS | Required by the Monkey C compiler and language server. |
| SDK | Connect IQ 9.2.0 | Installed via the Garmin SDK Manager. |

### Why not JetBrains?

Every JetBrains Monkey C plugin is abandoned. The Marketplace entry
([#8253](https://plugins.jetbrains.com/plugin/8253-monkey-c-garmin-connect-iq-))
was last updated **June 2018** and is self-described as unmaintained; the
[flocsy fork](https://github.com/flocsy/IntelliJ-MonkeyC-ConnectIQ-plugin)'s last
commit was **July 2021**; the [upstream repo](https://github.com/liias/monkey) is
archived. They also declare a `com.intellij.modules.java` dependency, so they load
only in IntelliJ IDEA.

JetBrains IDEs are still useful here for Git history, diffs, and any companion
web/mobile code — just not for editing Monkey C.

## Prerequisites

1. **JDK 21** — `winget install EclipseAdoptium.Temurin.21.JDK`; `JAVA_HOME` set.
2. **Connect IQ SDK** — install via the SDK Manager, then add
   `%APPDATA%\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-<version>\bin` to PATH.
3. **VS Code extensions** — `garmin.monkey-c`, `markw65.prettier-extension-monkeyc`.
4. **Developer key** — generated to `C:\Users\lasse\.garmin\developer_key`,
   deliberately **outside this repo**.

## Developer key

The key is your publishing identity for the Connect IQ store. It is stored outside
the repo and referenced by `StarterField/.vscode/settings.json`. `.gitignore` also blocks
`*developer_key*` as a safety net.

**Back it up.** Losing it means you cannot publish updates to an existing store
listing under the same identity.

## Target devices

| Device | Compiler ID | Display | Tech |
|---|---|---|---|
| fēnix 8 43mm | `fenix843mm` | 416×416 | AMOLED |
| fēnix 8 47mm / 51mm | `fenix847mm` | 454×454 | AMOLED |
| fēnix 8 Solar 47mm | `fenix8solar47mm` | 260×260 | MIP, 64 colors |
| fēnix 8 Solar 51mm | `fenix8solar51mm` | 280×280 | MIP, 64 colors |
| Edge 850 | `edge850` | 420×600 | Transflective LCD, touch |

Compiler IDs are authoritative in
`%APPDATA%\Garmin\ConnectIQ\Devices\<device>\compiler.json` — Garmin's published
docs lag new hardware, so verify there.

All fēnix 8 variants are targeted even though only one is owned: the Solar
variants' 64-color MIP palette catches color choices that look fine on AMOLED and
wash out on MIP.

## Opening the project

Open **`Garmin.code-workspace`**, not the repo folder.

The Monkey C extension resolves a project by joining `project.manifest` from the
jungle onto the *workspace folder*. The compiler resolves that same path
relative to the *jungle file*. With only the repo root open the two disagree:
`monkeyc` finds `StarterField/manifest.xml` and builds, while the extension
looks for `Garmin\manifest.xml`, finds nothing, and refuses to start a debug
session — "Unable to find manifest.xml for the workspace Garmin".

No relative path satisfies both lookups, so each app is listed as its own
workspace folder instead. Add an entry per app as the repo grows. Opening
`StarterField/` directly works too; opening only the repo root does not.

Monkey C settings therefore live in `StarterField/.vscode/settings.json`, except
`monkeyC.javaPath`, which is window-scoped and has to sit in the workspace file.

Launch configurations follow the same rule. The repo root's
`.vscode/launch.json` is deliberately empty: the default `Run App` / `Run Tests`
entries it used to hold belonged to the root folder, so launching one sent the
extension looking for `Garmin\monkey.jungle` and it gave up with "Connect IQ
project not found. Be sure your project has a jungle file and the project's
Jungle Files setting is correct."

When a launch configuration does not identify a folder on its own, the extension
falls back to the workspace folder owning the **active editor**. So keep a file
under `StarterField/` focused when starting a debug session — pressing `F5` with
`README.md` or the workspace file in front produces the same error.

## Build and run

Use the VS Code command palette:

- `Monkey C: Build Current Project` — produces `bin/<AppName>.prg`
- `Monkey C: Run App` / `F5` — build, launch the simulator, and attach the debugger
- `Monkey C: Export Project` — produce a `.iq` file for store upload

## Unit tests

Functions marked `(:test)` are compiled in only with the `-t` flag and are
stripped from debug and release builds, so they can sit beside the code they
exercise. The Test Explorer in VS Code runs them; from a shell it takes three
steps, because the test runner lives inside the simulator:

```sh
monkeyc -f StarterField/monkey.jungle -d fenix847mm \
    -o StarterField/bin/StarterFieldTest.prg \
    -y ~/.garmin/developer_key -t -l 3 -w
connectiq                                   # launch the simulator, no arguments
monkeydo StarterField/bin/StarterFieldTest.prg fenix847mm -t
```

The simulator must already be running when `monkeydo` is called. Append a
function name after `-t` to run a single test.

## Sideloading to hardware

Build for the specific device, then copy `bin/<AppName>.prg` to `GARMIN\APPS\` on
the device.

Current fēnix and Edge units mount over **MTP**, not as a drive letter, so this is
an Explorer drag rather than a scriptable `cp`. Do not assume a drive path in build
scripts.

After copying, add the data field to an activity data screen on the device to see
it render.
