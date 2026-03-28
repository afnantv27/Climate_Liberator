# Climate Liberator macOS App

This folder hosts the SwiftUI front end that sits on top of the Cell2Fire CLI.

## Layout

```
Climate-Liberator/
├─ Cell2Fire/               # original engine, builds with g++-15
├─ data/                    # sample inputs
└─ ClimateLiberatorApp/
   ├─ ClimateLiberator/          # Xcode project
   └─ scripts/              # helper scripts
```

## Building Cell2Fire

Use the helper script so every release uses the Homebrew GCC toolchain:

```bash
cd /Users/afnan/Desktop/Climate-Liberator/ClimateLiberatorApp
./scripts/build_cell2fire.sh
```

This script cleans and rebuilds `Cell2Fire` using `/opt/homebrew/bin/g++-15` (override with `$CXX`).

## Running the UI

1. Open `ClimateLiberatorApp/ClimateLiberator/ClimateLiberator.xcodeproj` (or the workspace) in Xcode.
2. Build & run. The first launch prompts for:
   - **Cell2Fire binary** – defaults to `../Cell2Fire/Cell2Fire/Cell2Fire`. Use the picker to browse if needed.
   - **Input folder** – defaults to `../data/ScottAndBurgan/Clinge`.
   - Optional output folder, theme, thread counts, etc.
3. Hit **Run Cell2Fire**. Logs stream into the text area; ROS GeoTIFF conversion runs automatically if selected.

All paths accept `~` or relative entries and are persisted via `AppStorage`.
