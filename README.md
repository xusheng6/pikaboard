# Pikaboard

A Xiangqi (Chinese chess) analysis app powered by the [Pikafish](https://github.com/official-pikafish/Pikafish) engine. Built with Flutter for iOS.

## Features

- Interactive Xiangqi board with Chinese character pieces
- Engine analysis with real-time search info (depth, score, nodes, NPS, time)
- PV (principal variation) displayed in traditional Chinese notation
- Best move highlighting on the board
- Move history with back/forward navigation
- FEN import/export
- Position setup mode

## Architecture

```
Flutter UI (Dart)
    ↓ dart:ffi
C Bridge (pikafish_bridge/) — thin C-linkage wrapper
    ↓ C++ calls
Pikafish Engine (Pikafish/src/) — static library
```

iOS cannot spawn subprocesses, so Pikafish is compiled as a static library (`libpikafish.a`) and linked into the app. Dart FFI calls the C bridge functions directly via `DynamicLibrary.process()`.

## Prerequisites

- macOS with Apple Silicon
- Xcode (with iOS simulator runtime installed)
- Flutter SDK (3.x)
- Git

## Build Instructions

### 1. Clone the repository

```bash
git clone --recursive git@github.com:xusheng6/pikaboard.git
cd pikaboard
```

If you already cloned without `--recursive`:

```bash
git submodule update --init
```

### 2. Obtain the NNUE network file

Download `pikafish.nnue` (~51MB) from the [Pikafish releases](https://github.com/official-pikafish/Pikafish/releases) and place it at:

```
app/assets/pikafish.nnue
```

### 3. Build the static library

For iOS Simulator (Apple Silicon Mac):

```bash
bash build_pikafish.sh ios-simulator
```

For a physical iOS device:

```bash
bash build_pikafish.sh ios
```

For macOS (native, useful for testing compilation):

```bash
bash build_pikafish.sh macos
```

The output is `build/<target>/libpikafish.a`.

### 4. Build and run the Flutter app

```bash
cd app
flutter pub get
flutter build ios --simulator --no-codesign
```

To run on a booted simulator:

```bash
flutter run
```

## Project Structure

```
pikaboard/
├── docs/
│   ├── xqf-format.md          # The XQF game record format, documented
│   └── xqf.ksy                # ... and as a Kaitai Struct definition
├── Pikafish/                  # Engine source (git submodule)
├── pikafish_bridge/
│   ├── pikafish_bridge.h      # C-linkage API header
│   └── pikafish_bridge.cpp    # Bridge implementation
├── build_pikafish.sh          # Build script for libpikafish.a
├── build/                     # Build output (gitignored)
└── app/                       # Flutter project
    ├── assets/
    │   └── pikafish.nnue      # NNUE weights (gitignored, download separately)
    ├── lib/
    │   ├── main.dart
    │   ├── engine/
    │   │   ├── pikafish_bindings.dart   # dart:ffi bindings
    │   │   ├── pikafish_engine.dart     # High-level engine API with Streams
    │   │   └── search_info.dart        # SearchInfo, BestMove data classes
    │   ├── models/
    │   │   ├── piece.dart              # Piece types and Chinese labels
    │   │   ├── position.dart           # Board position and FEN handling
    │   │   └── move_notation.dart      # UCI to Chinese notation converter
    │   └── ui/
    │       ├── app.dart                # Main app screen
    │       ├── board_widget.dart       # Board rendering (CustomPaint)
    │       └── analysis_panel.dart     # Search info display
    └── ios/
        └── Flutter/
            └── Pikafish.xcconfig       # Static library linkage config
```

## Documentation

- [The XQF game record format](docs/xqf-format.md) — the format XQStudio
  writes, reverse engineered from its source and checked against 399 files,
  with a [Kaitai Struct definition](docs/xqf.ksy) alongside it.

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).

This project uses [Pikafish](https://github.com/official-pikafish/Pikafish), which is licensed under GPL-3.0. The NNUE network file (`pikafish.nnue`) is licensed under a **non-commercial** clause — see the [Pikafish repository](https://github.com/official-pikafish/Pikafish) for details.
