#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
build_directory="$repository_root/.build"
iconset_directory="$build_directory/Arrowshot.iconset"
tiff_directory="$build_directory/ArrowshotIconTIFFs"
generator_binary="$build_directory/ArrowshotIconGenerator"
module_cache="$build_directory/ModuleCache"
output_icon="$repository_root/Resources/Arrowshot.icns"
architecture="$(uname -m)"

mkdir -p "$build_directory" "$module_cache"
if [[ -d "$iconset_directory" ]]; then
    rm -r "$iconset_directory"
fi
if [[ -d "$tiff_directory" ]]; then
    rm -r "$tiff_directory"
fi
mkdir -p "$tiff_directory"

CLANG_MODULE_CACHE_PATH="$module_cache" swiftc \
    -parse-as-library \
    -target "$architecture-apple-macosx14.0" \
    -module-cache-path "$module_cache" \
    "$repository_root/Scripts/IconGenerator.swift" \
    -framework AppKit \
    -o "$generator_binary"

"$generator_binary" "$iconset_directory"

icon_files=(
    icon_16x16.png
    icon_32x32.png
    icon_32x32@2x.png
    icon_128x128.png
    icon_256x256.png
    icon_512x512.png
    icon_512x512@2x.png
)
for icon_file in $icon_files; do
    sips -s format tiff \
        "$iconset_directory/$icon_file" \
        --out "$tiff_directory/${icon_file:r}.tiff" >/dev/null
done

tiffutil -cat "$tiff_directory"/*.tiff -out "$tiff_directory/Arrowshot.tiff" >/dev/null 2>&1
tiff2icns "$tiff_directory/Arrowshot.tiff" "$output_icon"
print "$output_icon"
