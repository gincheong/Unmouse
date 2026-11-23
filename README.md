# Unmouse

A macOS app for clicking buttons and links with the keyboard only. Press a shortcut and every clickable element gets a label. Type a label to click that element.

Label input is matched by key code, not by character. It works without switching the input source, even while a Korean or third-party input method is active.

## Features

- **Click mode**: shows labels on the windows, menus, and menu bar items of the frontmost app.
- **Scroll mode**: selects a scroll area and scrolls it with the keyboard.
- **Grid mode**: divides the screen into a grid and clicks any position, even in apps that expose no clickable elements.
- **Mission Control**: shows labels on window thumbnails and spaces when Mission Control opens.
- **Label design**: label characters, font, font weight, font size, padding, colors, corner radius, pointer arrow, and Liquid Glass can be changed in the settings window.

## Requirements

| Item                | Requirement                                                |
|---------------------|------------------------------------------------------------|
| Running             | macOS 13 or later                                          |
| Liquid Glass labels | macOS 26 or later                                          |
| Building            | Xcode or Command Line Tools with the macOS 26 SDK or later |

Mission Control labels were verified on macOS 27 only.

## Install

```sh
brew install --cask gincheong/tap/unmouse
```

On first launch the app asks for Accessibility permission. Turn on Unmouse in System Settings > Privacy & Security > Accessibility.

The released app is ad-hoc signed and not notarized. After upgrading, turn Unmouse off and on again in the Accessibility list, because the signature changes with every release.

### Updating

```sh
brew update && brew upgrade --cask unmouse
```

`brew upgrade` alone can skip refreshing the tap and report that Unmouse is already up to date.

Unmouse asks GitHub for the latest release once a day and shows an item in its menu when a newer version exists. Turn this off in the General tab of the settings window, where you can also check manually.

## Build and run

```sh
./build.sh
open build/Unmouse.app
```

### Signing

`build.sh` uses ad-hoc signing by default. An ad-hoc signature changes on every build, so Accessibility permission has to be granted again after each build.

If your keychain has a code signing certificate, pass its name when building. The permission then stays valid across rebuilds.

```sh
security find-identity -v -p codesigning
UNMOUSE_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build.sh
```

### Releasing

The cask lives in [gincheong/homebrew-tap](https://github.com/gincheong/homebrew-tap). Clone it next to this repository, or set `UNMOUSE_TAP_DIR` to its path.

Bump `CFBundleShortVersionString` in `Info.plist`, add the release to `CHANGELOG.md` and `docs/changelog.html`, then run `./release.sh`. It builds a universal app, writes `build/Unmouse.zip`, updates the version and checksum in the tap's `Casks/unmouse.rb`, and prints the commands for tagging, uploading the release, and pushing the tap.

## Usage

### Click mode

| Key                  | Action                          |
|----------------------|---------------------------------|
| `⌘'`                 | Turn click mode on or off       |
| Label characters     | Click the element               |
| `⇧` + last character | Right-click                     |
| `⌥` + last character | Double-click                    |
| `⌘` + last character | Command-click                   |
| `⌃` + last character | Move the cursor without clicking |
| `⌫`                  | Delete the last typed character |
| `ESC`                | Turn off                        |

### Scroll mode

| Key                    | Action                     |
|------------------------|----------------------------|
| `⇧⌘J`                  | Turn scroll mode on or off |
| `J` / `K`              | Down, up                   |
| `H` / `L`              | Left, right                |
| `D` / `U`              | Half page down, up         |
| `G` / `⇧G`             | Top, bottom                |
| `⇧` + direction key    | 3x speed                   |
| `1`–`9`                | Switch scroll area         |
| `ESC` or any other key | Turn off                   |

When there are several scroll areas, scrolling starts in the one under the cursor.

### Grid mode

| Key                  | Action                                  |
|----------------------|-----------------------------------------|
| `⇧⌘'`                | Turn grid mode on or off                |
| Two label characters | Select a cell and divide it again       |
| One more character   | Click that position                     |
| `↩` or `Space`       | Click the center of the selected cell   |
| `⌫`                  | Go back to the previous step            |
| `ESC`                | Turn off                                |

The grid covers the screen that has the cursor. The modifier keys of click mode work on the last key in the same way.

### Settings

Open `Settings…` from the Unmouse icon in the menu bar to change shortcuts, scroll speed, automatic labels in Mission Control, label design, and grid design. The settings window is in English by default and can be switched to Korean in the General tab.

## Limitations

- The Dock and other apps' menu bar icons do not get labels.
- In Chromium browsers and Electron apps, only some labels may appear while the accessibility tree is being built for the first time.
- Shortcuts may not work while secure input is on, such as in a password field.

## Development commands

Pass an argument to the executable to check behavior without launching the app.

```sh
BIN=build/Unmouse.app/Contents/MacOS/Unmouse

$BIN --check                       # permission state and generated labels
$BIN --scan [bundle id] [--scroll] # number of labeled elements and scan time
$BIN --mission-control             # whether Mission Control is open, and its elements
$BIN --preview [bundle id]         # show labels on screen for 3 seconds
$BIN --preview --grid              # show sample grid cells for 3 seconds
```

These run from the terminal, so the terminal app needs Accessibility permission.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) or the [changelog page](https://gincheong.github.io/Unmouse/changelog.html).

## License

[MIT](LICENSE)
