#!/usr/bin/env bash
set -euo pipefail
# Xcode GUI builds do not inherit the shell PATH, so add the standard Homebrew locations.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="${1:-$SCRIPT_DIR/../../Cell2Fire}"
OUTPUT="${2:-$SCRIPT_DIR/../build}"
CXX="${CXX:-$(xcrun --find clang++)}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="${CURRENT_ARCH:-$(uname -m)}"
if [[ "$ARCH" == undefined_arch ]]; then ARCH="$(uname -m)"; fi
BREW="${HOMEBREW_PREFIX:-$(brew --prefix)}"
OMP="$(brew --prefix libomp)"
TIFF="$(brew --prefix libtiff)"
BOOST="$(brew --prefix boost)"
mkdir -p "$OUTPUT/lib" "$OUTPUT/include" "$OUTPUT/obj" "$OUTPUT/bin"
FLAGS=(-std=c++14 -stdlib=libc++ -O3 -fPIC -fno-strict-aliasing -fexceptions -DNDEBUG -DIL_STD
    -isysroot "$SDK" -arch "$ARCH" "-mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET:-26.2}"
    -I"$BREW/include" -I"$OMP/include" -I"$TIFF/include" -I"$BOOST/include" -Xpreprocessor -fopenmp)
SIGNATURE="$(printf '%s\n' "$CXX" "$("$CXX" --version)" "${FLAGS[@]}")"
SIGNATURE_FILE="$OUTPUT/obj/build-signature.txt"
REBUILD=0
if [[ ! -f "$SIGNATURE_FILE" ]] || [[ "$(<"$SIGNATURE_FILE")" != "$SIGNATURE" ]]; then REBUILD=1; fi
SRCS=(Cell2Fire Cells DataGenerator FuelModelFBP FuelModelKitral FuelModelPortugal FuelModelRegistry
      FuelModelSpain FuelModelUtils Lightning ReadArgs ReadCSV Spotting WriteCSV cell2fire_api)
OBJS=()
CLI_OBJS=()
for name in "${SRCS[@]}"; do
    obj="$OUTPUT/obj/$name.o"
    if [[ "$REBUILD" == 1 || ! -f "$obj" || "$SOURCE/$name.cpp" -nt "$obj" ]] ||
       [[ -n "$(find "$SOURCE" -maxdepth 1 -name '*.h' -newer "$obj" -print 2>/dev/null || true)" ]]; then
        echo "Compiling $name"
        "$CXX" "${FLAGS[@]}" -DCELL2FIRE_LIBRARY -c "$SOURCE/$name.cpp" -o "$obj"
    fi
    OBJS+=("$obj")
    if [[ "$name" != Cell2Fire && "$name" != cell2fire_api ]]; then CLI_OBJS+=("$obj"); fi
done
main="$OUTPUT/obj/Cell2Fire-cli.o"
if [[ "$REBUILD" == 1 || ! -f "$main" || "$OUTPUT/obj/Cell2Fire.o" -nt "$main" ]]; then
    "$CXX" "${FLAGS[@]}" -c "$SOURCE/Cell2Fire.cpp" -o "$main"
fi
if [[ "$REBUILD" == 1 || ! -f "$OUTPUT/lib/libcell2fire.a" || ! -f "$OUTPUT/bin/Cell2Fire" ]] ||
   [[ -n "$(find "$OUTPUT/obj" -name '*.o' -newer "$OUTPUT/lib/libcell2fire.a" -print 2>/dev/null || true)" ]]; then
    xcrun ar rcs "$OUTPUT/lib/libcell2fire.a" "${OBJS[@]}"
    "$CXX" "${FLAGS[@]}" "$main" "${CLI_OBJS[@]}" -L"$OMP/lib" -lomp -L"$TIFF/lib" -ltiff -lm -lpthread -Wl,-headerpad_max_install_names -o "$OUTPUT/bin/Cell2Fire"
fi
cp "$SOURCE/cell2fire_api.h" "$OUTPUT/include/"
install -m 755 "$OMP/lib/libomp.dylib" "$OUTPUT/lib/libomp.dylib"
install -m 755 "$TIFF/lib/libtiff.dylib" "$OUTPUT/lib/libtiff.dylib"
printf '%s\n' "$SIGNATURE" > "$SIGNATURE_FILE"
