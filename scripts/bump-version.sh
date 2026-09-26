#!/bin/zsh
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $(basename "$0") <marketing-version> <build-number>" >&2
  exit 1
fi

MARKETING_VERSION="$1"
BUILD_NUMBER="$2"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$PROJECT_DIR/Config/Version.xcconfig"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "Missing version file: $VERSION_FILE" >&2
  exit 1
fi

/usr/bin/sed -i '' \
  -e "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $MARKETING_VERSION/" \
  -e "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $BUILD_NUMBER/" \
  "$VERSION_FILE"

echo "MARKETING_VERSION = $MARKETING_VERSION"
echo "CURRENT_PROJECT_VERSION = $BUILD_NUMBER"
