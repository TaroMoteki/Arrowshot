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
    Sources/Arrowshot/Support/Geometry.swift \
    Sources/Arrowshot/Support/ImageExtensions.swift \
    Sources/Arrowshot/Support/PixelExactImageRenderer.swift \
    Sources/Arrowshot/Support/ArrowshotStyle.swift \
    Sources/Arrowshot/Support/EditorCursors.swift \
    Sources/Arrowshot/Support/ArrowGeometry.swift \
    Sources/Arrowshot/Editor/Annotation.swift \
    Sources/Arrowshot/Capture/ScreenCoordinates.swift \
    Sources/Arrowshot/Capture/CaptureOutputSizing.swift \
    Sources/Arrowshot/Capture/OverlayWindowGeometry.swift \
    Tests/CoreLogicSmokeTests.swift \
    -framework AppKit \
    -framework CoreImage \
    -o "$test_binary"

"$test_binary"
