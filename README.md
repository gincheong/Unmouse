# Unmouse

키보드만으로 화면의 버튼과 링크를 클릭하는 macOS 앱입니다. 단축키를 누르면 클릭할 수 있는 요소마다 라벨이 표시되고, 라벨의 글자를 입력하면 해당 요소를 클릭합니다.

라벨 입력을 문자가 아닌 키코드로 판별합니다. 한글 입력기나 서드파티 입력기를 쓰는 중에도 입력 소스를 바꾸지 않고 동작합니다.

## 기능

- **클릭 모드**: 맨 앞 앱의 창과 메뉴, 메뉴바 항목에 라벨을 표시합니다.
- **스크롤 모드**: 스크롤 영역을 선택해서 키보드로 스크롤합니다.
- **Mission Control**: Mission Control이 열리면 창 썸네일과 스페이스에 라벨을 표시합니다.
- **라벨 디자인**: 라벨 문자, 글자 크기, 색, 모서리 둥글기, 화살표, Liquid Glass를 설정 창에서 바꿉니다.

## 요구 사항

| 항목 | 조건 |
|---|---|
| 실행 | macOS 13 이상 |
| Liquid Glass 라벨 | macOS 26 이상 |
| 빌드 | Xcode 또는 Command Line Tools, macOS 26 이상 SDK |

Mission Control 라벨은 macOS 27에서 확인했습니다. macOS 26 이하에서는 확인하지 못했습니다.

## 빌드와 실행

```sh
./build.sh
open build/Unmouse.app
```

처음 실행하면 손쉬운 사용 권한을 요청합니다. 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 Unmouse를 켜면 바로 동작합니다.

### 서명

`build.sh`는 기본으로 임시 서명을 사용합니다. 임시 서명은 빌드할 때마다 서명이 바뀌어서 손쉬운 사용 권한을 다시 켜야 합니다.

키체인에 코드 서명 인증서가 있으면 인증서 이름을 지정해서 빌드합니다. 이렇게 하면 다시 빌드해도 권한이 유지됩니다.

```sh
security find-identity -v -p codesigning
UNMOUSE_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build.sh
```

## 사용법

### 클릭 모드

| 키 | 동작 |
|---|---|
| `⌘'` | 클릭 모드 켜기, 끄기 |
| 라벨 글자 | 해당 요소 클릭 |
| `⇧` + 마지막 글자 | 우클릭 |
| `⌥` + 마지막 글자 | 더블클릭 |
| `⌘` + 마지막 글자 | 커맨드 클릭 |
| `⌫` | 입력한 글자 하나 지우기 |
| `ESC` | 끄기 |

### 스크롤 모드

| 키 | 동작 |
|---|---|
| `⇧⌘J` | 스크롤 모드 켜기, 끄기 |
| `J` / `K` | 아래, 위 |
| `H` / `L` | 왼쪽, 오른쪽 |
| `D` / `U` | 반 페이지 아래, 위 |
| `G` / `⇧G` | 맨 위, 맨 아래 |
| `⇧` + 방향 키 | 3배 속도 |
| `1`~`9` | 스크롤 영역 바꾸기 |
| `ESC` 또는 다른 키 | 끄기 |

스크롤 영역이 여러 개면 커서가 놓인 영역부터 시작합니다.

### 설정

메뉴바의 Unmouse 아이콘에서 `설정…`을 엽니다. 단축키, 스크롤 속도, Mission Control 자동 표시, 라벨 디자인을 바꿀 수 있고 변경한 값은 바로 적용됩니다.

## 제한 사항

- 검색 모드는 없습니다.
- Dock과 다른 앱의 메뉴바 아이콘에는 라벨을 표시하지 않습니다.
- Chromium 브라우저와 Electron 앱은 접근성 트리를 처음 만드는 동안 라벨이 일부만 표시될 수 있습니다.
- 암호 입력란처럼 보안 입력이 켜진 상태에서는 단축키가 동작하지 않을 수 있습니다.

## 개발용 명령

실행 파일에 인자를 주면 앱을 띄우지 않고 동작을 점검합니다.

```sh
BIN=build/Unmouse.app/Contents/MacOS/Unmouse

$BIN --check                       # 권한 상태와 라벨 생성 결과
$BIN --scan [bundle id] [--scroll] # 라벨이 붙을 요소 수와 스캔 시간
$BIN --mission-control             # Mission Control 열림 여부와 요소 목록
$BIN --preview [bundle id]         # 라벨을 3초 동안 화면에 표시
```

터미널에서 실행하므로 터미널 앱에 손쉬운 사용 권한이 있어야 합니다.

## 아이콘 다시 만들기

```sh
swift icon/make-icon.swift icon/AppIcon.iconset
iconutil -c icns icon/AppIcon.iconset -o icon/AppIcon.icns
./build.sh
```

## 라이선스

[MIT](LICENSE)

_Written by Claude_
