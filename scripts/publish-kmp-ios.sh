#!/bin/bash
#
# Publish KMP iOS XCFramework: stage fat .a files, Gradle build
#
# Usage: ./scripts/publish-kmp-ios.sh \
#          --root-dir /path/to/project \
#          --target-dir target-ios \
#          --abi arm64-ios-device --fat-lib /path/to/device/librgss_runtime.a \
#          --abi arm64-ios-simulator --fat-lib /path/to/simulator/librgss_runtime.a
#
# Arguments come in --abi/--fat-lib pairs. The ABI name determines the
# iosLibs subdirectory (ios_arm64 for device, ios_simulator_arm64 for simulator).

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

# Resolve TARGET_DIR to absolute path so it works after cd
case "$TARGET_DIR" in
	/*) ;;
	*) TARGET_DIR="$ROOT_DIR/$TARGET_DIR" ;;
esac

if [ ${#ABIS[@]} -ne ${#FAT_LIBS[@]} ]; then
	echo "Error: --abi and --fat-lib must be provided in pairs"
	exit 1
fi

if [ ${#ABIS[@]} -eq 0 ]; then
	echo "Error: at least one --abi/--fat-lib pair is required"
	exit 1
fi

KMP_PUBLISH_DIR="$ROOT_DIR/external/embedded-ruby-vm/kmp-publish"

# Phase 1: Stage fat libraries into iosLibs
rm -rf "$KMP_PUBLISH_DIR/src/main/iosLibs"

for i in "${!ABIS[@]}"; do
	abi="${ABIS[$i]}"
	fat_lib="${FAT_LIBS[$i]}"

	if [ ! -f "$fat_lib" ]; then
		echo "Error: Fat library not found at $fat_lib"
		exit 1
	fi

	case "$abi" in
		*ios-device*|*iphoneos*)       IOS_DIR="ios_arm64" ;;
		*ios-simulator*|*iphonesimulator*) IOS_DIR="ios_simulator_arm64" ;;
		*) echo "Error: Unknown iOS ABI '$abi'"; exit 1 ;;
	esac

	echo "Staging $abi → $IOS_DIR ($(du -h "$fat_lib" | cut -f1))"
	mkdir -p "$KMP_PUBLISH_DIR/src/main/iosLibs/$IOS_DIR"
	cp "$fat_lib" "$KMP_PUBLISH_DIR/src/main/iosLibs/$IOS_DIR/"
done

# Phase 2: Build XCFramework via Gradle
echo "--- Building XCFramework ---"
cd "$KMP_PUBLISH_DIR"
./gradlew assembleRubyVMReleaseXCFramework \
	-PnativeLibraryName=rgss_runtime
cd "$ROOT_DIR"

echo ""
echo "XCFramework built successfully"

# Phase 3: Publish KMP metadata module + iOS klibs via Gradle
# The metadata module enables consumers to use a single commonMain dependency
# that Gradle auto-resolves per target platform.
echo "--- Publishing KMP metadata module + iOS klibs ---"
cd "$KMP_PUBLISH_DIR"
./gradlew publishKotlinMultiplatformPublicationToMavenLocal \
	publishIosArm64PublicationToMavenLocal \
	publishIosSimulatorArm64PublicationToMavenLocal \
	-PnativeLibraryName=rgss_runtime
cd "$ROOT_DIR"

echo ""
echo "KMP metadata + iOS klibs published to Maven Local"
find "$HOME/.m2/repository/com/scorbutics/rubyvm/kmp-publish" -maxdepth 2 -type f 2>/dev/null | head -10
find "$HOME/.m2/repository/com/scorbutics/rubyvm/kmp-publish-iosarm64" -type f 2>/dev/null | head -10
find "$HOME/.m2/repository/com/scorbutics/rubyvm/kmp-publish-iossimulatorarm64" -type f 2>/dev/null | head -10

# Phase 4: Package iOS native static libraries for Maven distribution
# Consumers need these .a files at link time when building their iOS framework.
echo "--- Packaging iOS native libraries ---"
mkdir -p "$TARGET_DIR/native-ios"
for i in "${!ABIS[@]}"; do
	abi="${ABIS[$i]}"
	fat_lib="${FAT_LIBS[$i]}"

	case "$abi" in
		*ios-device*|*iphoneos*)       NATIVE_ID="native-iosarm64" ;;
		*ios-simulator*|*iphonesimulator*) NATIVE_ID="native-iossimulatorarm64" ;;
		*) continue ;;
	esac

	echo "Packaging $NATIVE_ID"
	NATIVE_DIR="$TARGET_DIR/native-ios/$NATIVE_ID"
	mkdir -p "$NATIVE_DIR"
	cp "$fat_lib" "$NATIVE_DIR/"
	(cd "$NATIVE_DIR" && zip -r "$TARGET_DIR/native-ios/${NATIVE_ID}.zip" .)
	rm -rf "$NATIVE_DIR"
done
echo "Native iOS libraries:"
ls -lh "$TARGET_DIR/native-ios/"

# Phase 5: Copy artifacts to target dir
mkdir -p "$TARGET_DIR/xcframework"
cp -r "$KMP_PUBLISH_DIR/build/XCFrameworks/release/"* "$TARGET_DIR/xcframework/"
find "$TARGET_DIR/xcframework" -type f | head -20

# Copy Maven artifacts (metadata + iOS klibs)
mkdir -p "$TARGET_DIR/maven-kmp/"
cp -r "$HOME/.m2/repository/com/scorbutics/rubyvm/kmp-publish" \
	"$TARGET_DIR/maven-kmp/" 2>/dev/null || true
cp -r "$HOME/.m2/repository/com/scorbutics/rubyvm/kmp-publish-iosarm64" \
	"$TARGET_DIR/maven-kmp/" 2>/dev/null || true
cp -r "$HOME/.m2/repository/com/scorbutics/rubyvm/kmp-publish-iossimulatorarm64" \
	"$TARGET_DIR/maven-kmp/" 2>/dev/null || true
