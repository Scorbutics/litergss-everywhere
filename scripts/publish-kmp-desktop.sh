#!/bin/bash
#
# Publish KMP Desktop JAR: wrap fat .a → .so, stage, Gradle publish
#
# Usage: ./scripts/publish-kmp-desktop.sh \
#          --root-dir /path/to/project \
#          --target-dir target \
#          --abi x86_64-linux --fat-lib /path/to/librgss_runtime.a \
#          [--abi arm64-linux --fat-lib /path/to/librgss_runtime.a]
#
# Arguments come in --abi/--fat-lib pairs (one per ABI to stage).
# The script builds a .so wrapper for each, stages them into kmp-publish,
# then runs a single Gradle publish.

set -e

ROOT_DIR=""
TARGET_DIR=""
ABIS=()
FAT_LIBS=()

while [ $# -gt 0 ]; do
	case "$1" in
		--root-dir)   ROOT_DIR="$2"; shift 2 ;;
		--target-dir) TARGET_DIR="$2"; shift 2 ;;
		--abi)        ABIS+=("$2"); shift 2 ;;
		--fat-lib)    FAT_LIBS+=("$2"); shift 2 ;;
		*) echo "Unknown argument: $1"; exit 1 ;;
	esac
done

if [ -z "$ROOT_DIR" ] || [ -z "$TARGET_DIR" ]; then
	echo "Error: --root-dir and --target-dir are required"
	exit 1
fi

if [ ${#ABIS[@]} -ne ${#FAT_LIBS[@]} ]; then
	echo "Error: --abi and --fat-lib must be provided in pairs"
	exit 1
fi

if [ ${#ABIS[@]} -eq 0 ]; then
	echo "Error: at least one --abi/--fat-lib pair is required"
	exit 1
fi

KMP_PUBLISH_DIR="$ROOT_DIR/external/embedded-ruby-vm/kmp-publish"

# Phase 1: Build .so wrapper and stage for each ABI
for i in "${!ABIS[@]}"; do
	abi="${ABIS[$i]}"
	fat_lib="${FAT_LIBS[$i]}"

	if [ ! -f "$fat_lib" ]; then
		echo "Error: Fat library not found at $fat_lib"
		exit 1
	fi
	echo "Found fat library for $abi ($(du -h "$fat_lib" | cut -f1))"

	WRAPPER_BUILD_DIR="$ROOT_DIR/build-kmp-desktop-wrapper-$abi"
	echo "--- Building librgss_runtime.so wrapper for $abi ---"
	cmake \
		-S "$KMP_PUBLISH_DIR/wrapper" \
		-B "$WRAPPER_BUILD_DIR" \
		-DTARGET_ABI="$abi" \
		-DFAT_LIB_PATH="$(realpath "$fat_lib")" \
		-DCMAKE_BUILD_TYPE=Release
	cmake --build "$WRAPPER_BUILD_DIR"

	case "$abi" in
		x86_64-linux|linux-x86_64) NATIVES_DIR="linux-x64" ;;
		arm64-linux|linux-arm64|aarch64-linux) NATIVES_DIR="linux-arm64" ;;
		arm64-macos|macos-arm64|aarch64-apple-darwin|arm64-apple-darwin) NATIVES_DIR="macos-arm64" ;;
		x86_64-macos|macos-x86_64) NATIVES_DIR="macos-x64" ;;
		*) NATIVES_DIR="$abi" ;;
	esac

	# Determine shared library extension based on platform
	case "$NATIVES_DIR" in
		macos-*) LIB_EXT="dylib" ;;
		*)       LIB_EXT="so" ;;
	esac

	echo "--- Staging .${LIB_EXT} into desktopLibs/natives/$NATIVES_DIR/ ---"
	mkdir -p "$KMP_PUBLISH_DIR/src/main/desktopLibs/natives/$NATIVES_DIR"
	cp "$WRAPPER_BUILD_DIR/librgss_runtime.${LIB_EXT}" \
		"$KMP_PUBLISH_DIR/src/main/desktopLibs/natives/$NATIVES_DIR/"
	ls -lh "$KMP_PUBLISH_DIR/src/main/desktopLibs/natives/$NATIVES_DIR/"
done

# Phase 2: Single Gradle publish with all ABIs
echo "--- Publishing Desktop JAR ---"
cd "$KMP_PUBLISH_DIR"
./gradlew publishDesktopPublicationToMavenLocal \
	-PnativeLibraryName=rgss_runtime
cd "$ROOT_DIR"

echo ""
echo "Desktop JAR published to Maven Local"
find "$HOME/.m2/repository/com/scorbutics/rubyvm/kmp-publish-desktop" -type f 2>/dev/null | head -10

# Phase 3: Copy Maven artifacts to target dir
mkdir -p "$TARGET_DIR/maven/"
cp -r "$HOME/.m2/repository/com/scorbutics/rubyvm/kmp-publish-desktop" \
	"$TARGET_DIR/maven/" 2>/dev/null || true
