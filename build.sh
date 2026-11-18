#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

# 임시 서명(-)은 빌드마다 서명이 바뀌어서 손쉬운 사용 권한을 매번 다시 줘야 한다.
# UNMOUSE_SIGN_IDENTITY에 키체인의 인증서 이름을 넣으면 권한이 유지된다.
IDENTITY="${UNMOUSE_SIGN_IDENTITY:--}"
APP="build/Unmouse.app"

swift build -c release
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Unmouse "$APP/Contents/MacOS/Unmouse"
cp Info.plist "$APP/Contents/Info.plist"
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "$IDENTITY" "$APP"
echo "built: $PWD/$APP"
