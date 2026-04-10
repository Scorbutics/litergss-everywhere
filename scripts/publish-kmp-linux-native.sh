#!/bin/bash
#
# Publish KMP Linux Native klib: stage fat .a files, Gradle publish
#
# Usage: ./scripts/publish-kmp-linux-native.sh \
#          --root-dir /path/to/project \
#          --target-dir target-linux-x86_64 \
#          --abi x86_64-linux --fat-lib /path/to/librgss_runtime.a

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

# Phase 1: Stage fat libraries into linuxNativeLibs
rm -rf "$KMP_PUBLISH_DIR/src/main/linuxNativeLibs"

for i in "${!ABIS[@]}"; do
	abi="${ABIS[$i]}"
	fat_lib="${FAT_LIBS[$i]}"

	if [ ! -f "$fat_lib" ]; then
		echo "Error: Fat library not found at $fat_lib"
		exit 1
	fi

	case "$abi" in
		x86_64-linux|linux-x86_64) LINUX_DIR="linux_x64" ;;
		arm64-linux|linux-arm64|aarch64-linux) LINUX_DIR="linux_arm64" ;;
		*) echo "Error: Unknown Linux ABI '$abi'"; exit 1 ;;
	esac

	echo "Staging $abi -> $LINUX_DIR ($(du -h "$fat_lib" | cut -f1))"
	mkdir -p "$KMP_PUBLISH_DIR/src/main/linuxNativeLibs/$LINUX_DIR"
	cp "$fat_lib" "$KMP_PUBLISH_DIR/src/main/linuxNativeLibs/$LINUX_DIR/"
done

# Phase 2: Publish Linux native klib via Gradle
echo "--- Publishing Linux Native klib ---"
cd "$KMP_PUBLISH_DIR"
./gradlew publishLinuxX64PublicationToMavenLocal \
	-PnativeLibraryName=rgss_runtime
cd "$ROOT_DIR"

echo ""
echo "Linux Native klib published to Maven Local"
find "$HOME/.m2/repository/com/scorbutics/rubyvm/kmp-publish-linuxx64" -type f 2>/dev/null | head -10

# Phase 3: Copy Maven artifacts to target dir
mkdir -p "$TARGET_DIR/maven-native/"
cp -r "$HOME/.m2/repository/com/scorbutics/rubyvm/kmp-publish-linuxx64" \
	"$TARGET_DIR/maven-native/" 2>/dev/null || true
