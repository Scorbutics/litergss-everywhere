#!/bin/bash
#
# Publish KMP Android AAR: wrap fat .a → .so, stage jniLibs, Gradle publish
#
# Usage: ./scripts/publish-kmp-android.sh \
#          --root-dir /path/to/project \
#          --target-dir target-android \
#          --abi arm64-v8a --fat-lib /path/to/arm64-v8a/librgss_runtime.a \
#          [--abi x86_64 --fat-lib /path/to/x86_64/librgss_runtime.a]
#
# Arguments come in --abi/--fat-lib pairs (one per Android ABI to stage).
# The script builds a .so wrapper for each using the Android NDK,
# stages them into jniLibs, then runs a single Gradle publish.

set -e

ROOT_DIR=""
TARGET_DIR=""
NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-}}"
ABIS=()
FAT_LIBS=()

while [ $# -gt 0 ]; do
	case "$1" in
		--root-dir)   ROOT_DIR="$2"; shift 2 ;;
		--target-dir) TARGET_DIR="$2"; shift 2 ;;
		--ndk-home)   NDK_HOME="$2"; shift 2 ;;
		--abi)        ABIS+=("$2"); shift 2 ;;
		--fat-lib)    FAT_LIBS+=("$2"); shift 2 ;;
		*) echo "Unknown argument: $1"; exit 1 ;;
	esac
done

if [ -z "$ROOT_DIR" ] || [ -z "$TARGET_DIR" ]; then
	echo "Error: --root-dir and --target-dir are required"
	exit 1
fi

if [ -z "$NDK_HOME" ]; then
	echo "Error: Android NDK not found. Set ANDROID_NDK_HOME or pass --ndk-home"
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

# Map ABI to NDK triple for finding libc++_shared.so
ndk_triple_for_abi() {
	case "$1" in
		arm64-v8a)    echo "aarch64-linux-android" ;;
		armeabi-v7a)  echo "arm-linux-androideabi" ;;
		x86_64)       echo "x86_64-linux-android" ;;
		x86)          echo "i686-linux-android" ;;
		*) echo "Error: Unknown ABI: $1" >&2; exit 1 ;;
	esac
}

# Clean stale jniLibs
rm -rf "$KMP_PUBLISH_DIR/src/main/jniLibs"

# Phase 1: Build .so wrapper and stage for each ABI
for i in "${!ABIS[@]}"; do
	abi="${ABIS[$i]}"
	fat_lib="${FAT_LIBS[$i]}"

	if [ ! -f "$fat_lib" ]; then
		echo "Error: Fat library not found at $fat_lib"
		exit 1
	fi
	echo ""
	echo "=== Building .so wrapper for $abi ==="
	echo "Found fat library ($(du -h "$fat_lib" | cut -f1))"

	NDK_TRIPLE=$(ndk_triple_for_abi "$abi")

	WRAPPER_BUILD_DIR="$ROOT_DIR/build-kmp-android-wrapper-$abi"
	cmake \
		-S "$KMP_PUBLISH_DIR/wrapper" \
		-B "$WRAPPER_BUILD_DIR" \
		-DCMAKE_TOOLCHAIN_FILE="$NDK_HOME/build/cmake/android.toolchain.cmake" \
		-DANDROID_ABI="$abi" \
		-DANDROID_PLATFORM=android-26 \
		-DANDROID_STL=c++_shared \
		-DTARGET_ABI="$abi" \
		-DFAT_LIB_PATH="$(realpath "$fat_lib")" \
		-DCMAKE_BUILD_TYPE=RelWithDebInfo

	if ! cmake --build "$WRAPPER_BUILD_DIR"; then
		echo "Failed to build librgss_runtime.so for $abi"
		exit 1
	fi

	echo "--- Staging .so into jniLibs/$abi/ ---"
	JNILIBS_DIR="$KMP_PUBLISH_DIR/src/main/jniLibs/$abi"
	mkdir -p "$JNILIBS_DIR"
	cp "$WRAPPER_BUILD_DIR/librgss_runtime.so" "$JNILIBS_DIR/"

	# Copy libc++_shared.so from NDK
	LIBCXX=$(find "$NDK_HOME/toolchains/llvm/prebuilt" -path "*$NDK_TRIPLE/libc++_shared.so" 2>/dev/null | head -1)
	if [ -n "$LIBCXX" ]; then
		cp "$LIBCXX" "$JNILIBS_DIR/libc++_shared.so"
	else
		echo "Warning: libc++_shared.so not found for $NDK_TRIPLE"
	fi

	echo "Staged files for $abi:"
	ls -lh "$JNILIBS_DIR/"*.so 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
done

# Show all staged ABIs
echo ""
echo "All staged ABIs:"
for abi_dir in "$KMP_PUBLISH_DIR/src/main/jniLibs"/*/; do
	abi_name=$(basename "$abi_dir")
	echo "  $abi_name: $(ls "$abi_dir"*.so 2>/dev/null | wc -l) libraries"
done

# Phase 2: Single Gradle publish with all ABIs
echo ""
echo "--- Publishing AAR with all ABIs ---"
cd "$KMP_PUBLISH_DIR"
./gradlew clean publishToMavenLocal -PnativeLibraryName=rgss_runtime
cd "$ROOT_DIR"

echo ""
echo "AAR published to Maven Local"
find "$HOME/.m2/repository/com/scorbutics/rubyvm/kmp-publish-android" -type f 2>/dev/null | head -10

# Phase 3: Copy Maven artifacts to target dir
mkdir -p "$TARGET_DIR/maven/"
if [ -d "$HOME/.m2/repository/com/scorbutics/rubyvm/kmp-publish-android" ]; then
	mkdir -p "$TARGET_DIR/maven/com/scorbutics/rubyvm/"
	cp -r "$HOME/.m2/repository/com/scorbutics/rubyvm/kmp-publish-android" \
		"$TARGET_DIR/maven/com/scorbutics/rubyvm/"
	echo "Maven artifacts exported to: $TARGET_DIR/maven/"
	echo ""
	echo "AAR contents:"
	AAR_FILE=$(find "$TARGET_DIR/maven" -name '*.aar' | head -1)
	if [ -n "$AAR_FILE" ]; then
		unzip -l "$AAR_FILE" 2>/dev/null | grep -E '\.so|jni/' | awk '{print "  " $4}'
	fi
else
	echo "Warning: Maven artifacts not found"
fi
