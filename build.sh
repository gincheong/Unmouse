#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

# 임시 서명(-)은 빌드마다 서명이 바뀌어서 손쉬운 사용 권한을 매번 다시 줘야 한다.
# UNMOUSE_SIGN_IDENTITY에 키체인의 인증서 이름을 넣으면 권한이 유지된다.
IDENTITY="${UNMOUSE_SIGN_IDENTITY:--}"
APP="build/Unmouse.app"

# 배포용 빌드는 Intel 맥에서도 실행돼야 해서 release.sh가 UNMOUSE_UNIVERSAL=1로 호출한다.
ARCH_FLAGS=()
[[ -n "${UNMOUSE_UNIVERSAL:-}" ]] && ARCH_FLAGS=(--arch arm64 --arch x86_64)

swift build -c release $ARCH_FLAGS
BIN_DIR="$(swift build -c release $ARCH_FLAGS --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Unmouse" "$APP/Contents/MacOS/Unmouse"
cp Info.plist "$APP/Contents/Info.plist"
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "$IDENTITY" "$APP"
echo "built: $PWD/$APP"
