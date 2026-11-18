#!/usr/bin/env bash
# Deletes the given SNAPSHOT versions of one package job's Maven packages
# before that job publishes them again (GitHub Packages refuses to overwrite).
#
#   delete-snapshots.sh <linux|apple> <version>...
#
# package-linux publishes the linux scope, package-apple every other package:
# each job deletes only its own, as the other may already have re-published.
# Needs GH_TOKEN. DRY_RUN=1 lists what it would delete.
set -uo pipefail

SCOPE="$1"; shift
OWNER="${GITHUB_REPOSITORY_OWNER}"
LINUX_PACKAGES="rgss-runtime-android rgss-runtime-desktop rgss-runtime-linuxx64"

echo "Deleting SNAPSHOT package versions ($*, ${SCOPE} packages) before re-publishing..."

# The owner is an organization or a user: try both. A failed call prints its
# error body on stdout: only the call that succeeds may print.
gh_api() {
  local path="$1" out; shift
  if out=$(gh api "$@" "/orgs/${OWNER}/${path}" 2>/dev/null); then
    printf '%s\n' "$out"
  else
    gh api "$@" "/users/${OWNER}/${path}" 2>/dev/null
  fi
}

PACKAGES=$(gh_api "packages?package_type=maven" --paginate --jq '.[].name') || PACKAGES=""

for VERSION in "$@"; do
  for PACKAGE in $PACKAGES; do
    # GitHub names them groupId.artifactId: compare the artifactId
    case " $LINUX_PACKAGES " in
      *" ${PACKAGE##*.} "*) PACKAGE_SCOPE=linux ;;
      *) PACKAGE_SCOPE=apple ;;
    esac
    [ "$PACKAGE_SCOPE" = "$SCOPE" ] || continue

    VERSION_ID=$(gh_api "packages/maven/${PACKAGE}/versions" --paginate \
      --jq ".[] | select(.name == \"${VERSION}\") | .id") || VERSION_ID=""
    [ -n "$VERSION_ID" ] || continue

    echo "Deleting ${PACKAGE}@${VERSION} (version ID: ${VERSION_ID})"
    [ -z "${DRY_RUN:-}" ] || continue
    # The last version of a package cannot be deleted: delete the package then
    if ! gh_api "packages/maven/${PACKAGE}/versions/${VERSION_ID}" --method DELETE; then
      echo "Version delete failed, trying to delete entire package ${PACKAGE}..."
      gh_api "packages/maven/${PACKAGE}" --method DELETE || echo "Warning: failed to delete ${PACKAGE}@${VERSION}"
    fi
  done
done
echo "SNAPSHOT cleanup complete."
