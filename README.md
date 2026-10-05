# Arrowshot

[日本語](README_ja.md)

Arrowshot is a lightweight macOS screenshot tool for pointing things out. Capture part of the screen, drop in a bold arrow or a label, and drag the result straight into a chat, an email, or a document. Inspired by the feel of Skitch.

Everything runs locally on your Mac. No account, no cloud, no network access.

> **Note:** The interface is currently in Japanese only. English localization is planned.

## Features

- **Skitch-style arrows** — a tapered shaft with a soft drop shadow, tuned to read clearly at a glance
- **Bold labels** — red text with a white outline and shadow, readable on any background
- **Rectangles, ellipses (optionally filled), lines, pixelation, and cropping** — crop can extend beyond the image edge
- **Drag to export** — drag the finished image from the toolbar straight into another app without saving a file
- **Global hotkeys** — work from any app, and can be changed in Settings
- **Retina quality** — captures keep the display's native pixels
- Zoom (pinch, ⌘+ / ⌘− / ⌘0), Shift to snap lines and arrows to 45°, undo/redo, PNG save, and clipboard copy

### Default shortcuts

| Action | Shortcut |
|---|---|
| Capture a region or window | ⌘⇧2 |
| Capture with a timer | ⌘⇧1 |
| Capture the full screen | ⌘⌥⇧3 |
| Settings | ⌘, |

In the editor, switch tools with A (arrow), T (text), R (rectangle), O (ellipse), L (line), M (pixelate), C (crop), or 1–7.

## Requirements

- macOS 14 Sonoma or later
- Apple silicon or Intel Mac (universal binary)
- Screen Recording permission

## Install

1. Download the latest `Arrowshot-x.y.z.zip` from [Releases](../../releases) and unzip it.
2. Move `Arrowshot.app` to your Applications folder.
3. The app is not notarized by Apple, so macOS will block the first launch. Open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**.
4. Press ⌘⇧2 and allow Screen Recording when asked. Quit and reopen Arrowshot once after granting it.

## Build from source

Requires Xcode.

```sh
Scripts/build-app.sh release
open .build/Arrowshot.app
```

macOS ties the Screen Recording permission to the app's code signature, so an ad-hoc build asks again after every rebuild. To keep the permission across rebuilds, create a stable self-signed certificate once:

```sh
Scripts/setup-signing.sh
```

This creates a certificate named "Arrowshot Local Signing" in your login keychain, then builds, signs, and installs the app to `/Applications`.

Run the tests:

```sh
swift test
Scripts/run-core-tests.sh
```

To build an installer package, run `Scripts/build-pkg.sh release`.

## Privacy

Arrowshot has no analytics, accounts, updater, or network code. Captures stay in memory until you save or copy them. See [PRIVACY.md](PRIVACY.md).

## Credits

Arrowshot is based on [PictoJot](https://github.com/sikkimtemi/PictoJot) by sikkimtemi, released under the MIT License. Thank you for the solid foundation.

## License

[MIT License](LICENSE)
