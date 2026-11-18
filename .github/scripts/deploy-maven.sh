#!/usr/bin/env bash
# Publishes one file to the repository's GitHub Packages Maven registry,
# under com.scorbutics.rubyvm.
#
#   deploy-maven.sh <artifactId> <version> <packaging> <dir> [optional]
#
# The file is the first *.<packaging> under <dir> (not a -sources one), its POM
# the first *.pom there (generated when there is none, except for a .module,
# which is skipped without one). Missing file: an error, or a warning with
# "optional". Maven settings: $MAVEN_SETTINGS (default /tmp/maven-settings.xml).
set -euo pipefail

ARTIFACT_ID="$1" VERSION="$2" PACKAGING="$3" DIR="$4" MODE="${5:-required}"

FILE=$(find "$DIR" -name "*.${PACKAGING}" ! -name '*-sources.*' 2>/dev/null | head -1)
POM=$(find "$DIR" -name '*.pom' 2>/dev/null | head -1)

if [ -z "$FILE" ] || { [ "$PACKAGING" = module ] && [ -z "$POM" ]; }; then
  if [ "$MODE" = optional ]; then
    echo "::warning::No .${PACKAGING} (or its POM) in $DIR: ${ARTIFACT_ID}:${VERSION} not published"
    find "$DIR" -type f 2>/dev/null || true
    exit 0
  fi
  echo "::error::No .${PACKAGING} in $DIR"
  exit 1
fi

ARGS=(
  -DgroupId=com.scorbutics.rubyvm
  -DartifactId="$ARTIFACT_ID"
  -Dversion="$VERSION"
  -Dpackaging="$PACKAGING"
  -Dfile="$FILE"
  -DrepositoryId=github
  -Durl="https://maven.pkg.github.com/${GITHUB_REPOSITORY}"
)
if [ -n "$POM" ]; then
  ARGS+=(-DpomFile="$POM")
else
  ARGS+=(-DgeneratePom=true)
fi

echo "Publishing com.scorbutics.rubyvm:${ARTIFACT_ID}:${VERSION} from $FILE"
mvn deploy:deploy-file "${ARGS[@]}" --settings "${MAVEN_SETTINGS:-/tmp/maven-settings.xml}"
