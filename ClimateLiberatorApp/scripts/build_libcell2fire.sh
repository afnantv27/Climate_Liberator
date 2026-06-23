#!/usr/bin/env bash
set -euo pipefail
#
# build_libcell2fire.sh — Pre-build script for Xcode
#
# Compiles Cell2Fire C++ engine into a static library (libcell2fire.a)
# that the ClimateLiberator SwiftUI app links directly.
#
# Usage:
#   ./scripts/build_libcell2fire.sh [CELL2FIRE_SRC_DIR] [OUTPUT_DIR]
#
# Defaults:
#   CELL2FIRE_SRC_DIR = ../Cell2Fire  (relative to this script's parent)
#   OUTPUT_DIR        = ./build       (relative to this script's parent)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CELL2FIRE_SRC="${1:-$(cd "$APP_ROOT/../Cell2Fire" 2>/dev/null && pwd || echo "")}"
OUTPUT_DIR="${2:-$APP_ROOT/build}"

if [[ -z "$CELL2FIRE_SRC" || ! -d "$CELL2FIRE_SRC" ]]; then
    echo "ERROR: Cell2Fire source directory not found." >&2
    echo "Pass it as first argument: $0 /path/to/Cell2Fire" >&2
    exit 1
fi

echo "=== Building libcell2fire.a ==="
echo "Source:  $CELL2FIRE_SRC"
echo "Output:  $OUTPUT_DIR"

mkdir -p "$OUTPUT_DIR/lib" "$OUTPUT_DIR/include"

# Detect compiler
#
# We deliberately use Apple clang++ (libc++) rather than Homebrew g++ (libstdc++).
# The ClimateLiberator app links this static library with the Xcode toolchain,
# which uses clang/libc++. Building the engine with g++ produces libstdc++
# (std::__cxx11) symbols that are ABI-incompatible and fail to link.
HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
if [[ -z "${CXX:-}" ]]; then
    CXX="$(xcrun -find clang++ 2>/dev/null || echo clang++)"
fi
echo "Compiler: $CXX"

# Flags
# Note: Apple clang needs -Xpreprocessor -fopenmp (not bare -fopenmp) for OpenMP,
# and links the runtime via -lomp (Homebrew libomp). When invoking clang++
# directly we must point it at the macOS SDK so it can find libc++ headers.
SDKROOT="$(xcrun --show-sdk-path 2>/dev/null || echo "")"
CXXFLAGS="-std=c++14 -stdlib=libc++ -O3 -fPIC -fno-strict-aliasing -fexceptions -DNDEBUG -DIL_STD -DCELL2FIRE_LIBRARY"
if [[ -n "$SDKROOT" ]]; then
    CXXFLAGS="$CXXFLAGS -isysroot $SDKROOT"
fi
CXXFLAGS="$CXXFLAGS -I$HOMEBREW_PREFIX/include"
CXXFLAGS="$CXXFLAGS -Xpreprocessor -fopenmp -I$HOMEBREW_PREFIX/opt/libomp/include"
CXXFLAGS="$CXXFLAGS -I$HOMEBREW_PREFIX/opt/libtiff/include"
CXXFLAGS="$CXXFLAGS -I$HOMEBREW_PREFIX/opt/boost/include"

# Source files
SRCS=(
    Cell2Fire.cpp
    Cells.cpp
    DataGenerator.cpp
    FuelModelFBP.cpp
    FuelModelKitral.cpp
    FuelModelPortugal.cpp
    FuelModelRegistry.cpp
    FuelModelSpain.cpp
    FuelModelUtils.cpp
    Lightning.cpp
    ReadArgs.cpp
    ReadCSV.cpp
    Spotting.cpp
    WriteCSV.cpp
    cell2fire_api.cpp
)

# Compile all source files
OBJ_DIR="$OUTPUT_DIR/obj"
mkdir -p "$OBJ_DIR"

OBJS=()
for src in "${SRCS[@]}"; do
    obj="$OBJ_DIR/${src%.cpp}.o"
    echo "  Compiling $src..."
    $CXX $CXXFLAGS -c "$CELL2FIRE_SRC/$src" -o "$obj"
    OBJS+=("$obj")
done

# Create static library
echo "  Archiving libcell2fire.a..."
ar rcs "$OUTPUT_DIR/lib/libcell2fire.a" "${OBJS[@]}"

# Copy header
cp "$CELL2FIRE_SRC/cell2fire_api.h" "$OUTPUT_DIR/include/"

echo ""
echo "=== Build complete ==="
ls -lh "$OUTPUT_DIR/lib/libcell2fire.a"
echo "Header:  $OUTPUT_DIR/include/cell2fire_api.h"
echo ""
echo "Xcode build settings needed:"
echo "  LIBRARY_SEARCH_PATHS = $OUTPUT_DIR/lib"
echo "  HEADER_SEARCH_PATHS  = $OUTPUT_DIR/include"
echo "  OTHER_LDFLAGS        = -lcell2fire -lgomp -ltiff -lm -lpthread"
