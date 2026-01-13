#!/bin/bash
#
# Validate AAR artifact from Maven Local repository
# Usage: ./scripts/validate-aar.sh [abi]
#
# This script checks that a published AAR contains:
# - Valid AndroidManifest.xml
# - classes.jar
# - Native libraries (.so files)
# - Proper structure
#

set -e

AAR_PATH="${1:-/root/.m2/repository/com/scorbutics/rubyvm/kmp-android/1.0.0-SNAPSHOT/kmp-android-1.0.0-SNAPSHOT.aar}"
CONTAINER="${CONTAINER:-litergss-everywhere_dev}"

echo "=========================================="
echo "AAR Validation Tool"
echo "=========================================="
echo "AAR Path: $AAR_PATH"
echo "Container: $CONTAINER"
echo ""

# Check if running in Docker mode
if [ -n "$CONTAINER" ] && docker ps --filter "name=$CONTAINER" --format "{{.Names}}" 2>/dev/null | grep -q "^$CONTAINER$"; then
    echo "Running in Docker mode, using container: $CONTAINER"
    DOCKER_EXEC="docker exec $CONTAINER"
else
    echo "Running in local mode"
    DOCKER_EXEC=""
fi

# Check if AAR exists
echo "Checking if AAR file exists..."
if ! $DOCKER_EXEC test -f "$AAR_PATH"; then
    echo "ERROR: AAR file not found at $AAR_PATH"
    exit 1
fi
echo "✓ AAR file exists"
echo ""

# Show file size
echo "AAR File Size:"
$DOCKER_EXEC ls -lh "$AAR_PATH" | awk '{print "  " $9 " (" $5 ")"}'
echo ""

# List contents
echo "AAR Contents:"
$DOCKER_EXEC unzip -l "$AAR_PATH" | tail -n +4 | head -n -2
echo ""

# Extract and validate AndroidManifest.xml
echo "AndroidManifest.xml:"
$DOCKER_EXEC bash -c "unzip -p '$AAR_PATH' AndroidManifest.xml 2>/dev/null" | head -20
echo ""

# Check for native libraries
echo "Native Libraries:"
$DOCKER_EXEC unzip -l "$AAR_PATH" | grep -E '\.so$' | awk '{print "  " $4 " (" $1 " bytes)"}'
echo ""

# Validate structure
echo "Structure Validation:"
HAS_MANIFEST=$($DOCKER_EXEC unzip -l "$AAR_PATH" | grep -c "AndroidManifest.xml" || echo 0)
HAS_CLASSES=$($DOCKER_EXEC unzip -l "$AAR_PATH" | grep -c "classes.jar" || echo 0)
HAS_NATIVE=$($DOCKER_EXEC unzip -l "$AAR_PATH" | grep -c "\.so$" || echo 0)

if [ "$HAS_MANIFEST" -gt 0 ]; then
    echo "  ✓ AndroidManifest.xml present"
else
    echo "  ✗ AndroidManifest.xml MISSING"
fi

if [ "$HAS_CLASSES" -gt 0 ]; then
    echo "  ✓ classes.jar present"
else
    echo "  ✗ classes.jar MISSING"
fi

if [ "$HAS_NATIVE" -gt 0 ]; then
    echo "  ✓ Native libraries present ($HAS_NATIVE files)"
else
    echo "  ⚠ No native libraries found"
fi

echo ""

# Final verdict
if [ "$HAS_MANIFEST" -gt 0 ] && [ "$HAS_CLASSES" -gt 0 ]; then
    echo "=========================================="
    echo "✓ AAR appears to be valid!"
    echo "=========================================="
    exit 0
else
    echo "=========================================="
    echo "✗ AAR validation failed"
    echo "=========================================="
    exit 1
fi
