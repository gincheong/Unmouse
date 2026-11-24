#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
ZIP="build/Unmouse.zip"
# cask는 gincheong/homebrew-tap 저장소에 있다. 클론 위치가 다르면 UNMOUSE_TAP_DIR로 지정한다.
TAP="${UNMOUSE_TAP_DIR:-../homebrew-tap}"
CASK="$TAP/Casks/unmouse.rb"

[[ -f "$CASK" ]] || { echo "cask not found: $CASK" >&2; exit 1; }

UNMOUSE_UNIVERSAL=1 ./build.sh
ditto -c -k --keepParent build/Unmouse.app "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"

sed -i '' -E \
  -e "s/^  version \".*\"/  version \"$VERSION\"/" \
  -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
  "$CASK"

# cask의 sha256은 이 zip에만 맞는다. 다시 빌드하면 값이 달라지므로 릴리즈에는 이 zip을 올린다.
cat <<EOF

version: $VERSION
sha256:  $SHA
zip:     $PWD/$ZIP
EOF
