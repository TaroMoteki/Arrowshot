#!/bin/zsh

set -euo pipefail

configuration="${1:-release}"
repository_root="${0:A:h:h}"
cd "$repository_root"

application_directory="$repository_root/.build/PictoJot.app"
contents_directory="$application_directory/Contents"
binary_path="$repository_root/.build/PictoJot"
bundle_identifier="${PICTOJOT_BUNDLE_IDENTIFIER:-io.github.sikkimtemi.PictoJot}"
signing_identity="${PICTOJOT_APP_SIGN_IDENTITY:--}"
architectures=(arm64 x86_64)

"$repository_root/Scripts/generate-app-icon.sh" >/dev/null
source_files=("$repository_root"/Sources/PictoJot/**/*.swift)
architecture_binaries=()

for architecture in $architectures; do
    architecture_binary="$repository_root/.build/PictoJot-$architecture"
    module_cache="$repository_root/.build/ModuleCache-$architecture"
    mkdir -p "$module_cache"

    compiler_flags=(-parse-as-library -target "$architecture-apple-macosx14.0" -module-cache-path "$module_cache")
    if [[ "$configuration" == "release" ]]; then
        compiler_flags+=(-O)
    else
        compiler_flags+=(-Onone -g)
    fi

    CLANG_MODULE_CACHE_PATH="$module_cache" swiftc \
        $compiler_flags \
        $source_files \
        -framework AppKit \
        -framework CoreImage \
        -framework ScreenCaptureKit \
        -framework ServiceManagement \
        -o "$architecture_binary"
    architecture_binaries+=("$architecture_binary")
done

lipo -create $architecture_binaries -output "$binary_path"
lipo "$binary_path" -verify_arch $architectures

if [[ -d "$application_directory" ]]; then
    rm -r "$application_directory"
fi

mkdir -p "$contents_directory/MacOS" "$contents_directory/Resources"
cp "$binary_path" "$contents_directory/MacOS/PictoJot"
cp "$repository_root/Resources/Info.plist" "$contents_directory/Info.plist"
cp "$repository_root/Resources/PictoJot.icns" "$contents_directory/Resources/PictoJot.icns"
plutil -replace CFBundleIdentifier -string "$bundle_identifier" "$contents_directory/Info.plist"
xattr -cr "$application_directory"
codesign_flags=(--force --sign "$signing_identity")
if [[ "$signing_identity" != "-" ]]; then
    codesign_flags+=(--options runtime --timestamp)
fi
codesign $codesign_flags "$application_directory"
codesign --verify --deep --strict "$application_directory"

print "$application_directory"
