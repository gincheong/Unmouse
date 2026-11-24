# Changelog

## 0.4.1 - 2026-11-24

### Fixed

- Click mode shows labels on web elements whose parent reports a height or width under 3px. Form inputs in some web layouts were skipped.

## 0.4.0 - 2026-11-23

### Added

- Update check: asks GitHub for the latest release once a day and shows a menu item with the Homebrew upgrade command when a newer version exists. The General tab has a toggle and a manual check.

### Fixed

- Unmouse stops handling keys when its Accessibility permission is turned off while it is running, and resumes when the permission is turned on again.

## 0.3.0 - 2026-11-23

### Changed

- Liquid Glass labels use the system regular glass. The hand-drawn gloss, glint, and iridescent rim are removed.
- Liquid Glass labels point at the target with a rounded bump in place of the triangle.
- Plain labels are drawn as keycaps: a face in the background color over a darker side. The label height grows by the side height.
- The settings preview shows the keycap design.

## 0.2.0 - 2026-11-23

### Added

- Click mode detects clickable web elements by their class and by the press action.
- Universal build for Apple silicon and Intel, and a Homebrew cask release script.

## 0.1.0 - 2026-11-19

### Added

- Click mode, with labels on the windows, menus, and menu bar items of the frontmost app.
- Scroll mode.
- Grid mode, with finer division and a grid that follows the focused window.
- Mission Control labels on window thumbnails and spaces.
- Hover with Control.
- Label design settings: characters, font, weight, size, padding, colors, opacity, corner radius, and Liquid Glass.
- Grid design settings.
- English and Korean localization.
- Settings synced to `~/.config/unmouse/config.json`.
