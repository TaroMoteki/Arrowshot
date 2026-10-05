#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
cd "$repository_root"

module_cache="$repository_root/.build/ModuleCache"
test_binary="$repository_root/.build/CoreLogicSmokeTests"
architecture="$(uname -m)"

mkdir -p "$module_cache"

CLANG_MODULE_CACHE_PATH="$module_cache" swiftc \
    -parse-as-library \
    -target "$architecture-apple-macosx14.0" \
    -module-cache-path "$module_cache" \
    Sources/PictoJot/Support/Geometry.swift \
    Sources/PictoJot/Support/ImageExtensions.swift \
    Sources/PictoJot/Support/PixelExactImageRenderer.swift \
    Sources/PictoJot/Support/PictoJotStyle.swift \
    Sources/PictoJot/Support/EditorCursors.swift \
    Sources/PictoJot/Support/ArrowGeometry.swift \
    Sources/PictoJot/Editor/Annotation.swift \
    Sources/PictoJot/Capture/ScreenCoordinates.swift \
    Sources/PictoJot/Capture/CaptureOutputSizing.swift \
    Sources/PictoJot/Capture/OverlayWindowGeometry.swift \
    Tests/CoreLogicSmokeTests.swift \
    -framework AppKit \
    -framework CoreImage \
    -o "$test_binary"

"$test_binary"
