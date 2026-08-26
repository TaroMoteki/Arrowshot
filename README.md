# PictoJot

[日本語](README_ja.md)

PictoJot is a native macOS menu-bar utility for capturing screenshots and adding lightweight annotations. Captures are processed locally, and no account or network connection is required.

![The PictoJot editor demonstrating arrows, shapes, text, pixelation, and cropping](docs/images/pictojot-overview.png)

## Requirements

- macOS 14 or later
- Apple Silicon or Intel Mac (Universal Binary)
- Screen Recording permission for screenshot capture

## Features

- Menu-bar residency, with the Dock icon and application menus shown while the editor is open
- An optional launch-at-login setting offered on first launch
- Rectangle and window capture across multiple displays
- Optional five-second timer after selecting a rectangle
- Drag and drop for common image formats
- Arrows, text, rectangles, ellipses, and lines
- Move, resize, and rotate annotations where applicable
- Annotation color and line-width controls
- Pixelation and cropping
- Undo and redo
- PNG export and clipboard copy

Freehand drawing and stamps are intentionally out of scope.

## Build

Generate a locally ad-hoc-signed application bundle:

```sh
Scripts/build-app.sh release
open .build/PictoJot.app
```

For a debug build:

```sh
Scripts/build-app.sh debug
```

You can override the development bundle identifier without changing tracked files:

```sh
PICTOJOT_BUNDLE_IDENTIFIER=org.example.PictoJot Scripts/build-app.sh release
```

For development with a complete Xcode installation, open `Package.swift` in Xcode or run:

```sh
swift test
```

The fallback core-logic test used by environments without XCTest is:

```sh
Scripts/run-core-tests.sh
```

## Installer package

Create a local test installer that places PictoJot in `/Applications` and launches it after installation:

```sh
Scripts/build-pkg.sh release
open .build/PictoJot-0.1.3.pkg
```

The default package and app use local test signatures. For public distribution, provide Developer ID Application and Installer identities:

```sh
PICTOJOT_APP_SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
PICTOJOT_INSTALLER_SIGN_IDENTITY="Developer ID Installer: Example (TEAMID)" \
Scripts/build-pkg.sh release
```

Public packages must also be notarized and stapled before release.

## Usage

1. Launch the app and select a capture command from its menu-bar icon.
2. Drag to select a rectangle, or click a window.
3. Choose an annotation tool from the left sidebar and drag on the image.
4. Hover over an existing annotation and click it to move or transform it.
5. Copy the result to the clipboard or save it as a PNG.

The timed mode waits five seconds only after rectangle selection. Press Escape or right-click to cancel selection.

## Privacy and security

The app has no analytics, account system, updater, or network code. Captures remain in memory until you explicitly save or copy them. See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md).

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## License

Source code is available under the [MIT License](LICENSE).
