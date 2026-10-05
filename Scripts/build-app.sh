#!/bin/zsh

set -euo pipefail

configuration="${1:-release}"
repository_root="${0:A:h:h}"
cd "$repository_root"

application_directory="$repository_root/.build/Arrowshot.app"
contents_directory="$application_directory/Contents"
binary_path="$repository_root/.build/Arrowshot"
bundle_identifier="${ARROWSHOT_BUNDLE_IDENTIFIER:-io.github.taromoteki.Arrowshot}"
# Prefer the stable local self-signed identity when it exists, so TCC permissions
# (e.g. Screen Recording) survive rebuilds. Falls back to ad-hoc otherwise.
default_signing_identity="-"
# Note: use `find-identity -p codesigning` WITHOUT `-v`; a self-signed cert is
# untrusted (CSSMERR_TP_NOT_TRUSTED) so `-v` (valid only) would hide it, even
# though codesign can still sign with it.
if security find-identity -p codesigning 2>/dev/null | grep -q "Arrowshot Local Signing"; then
    default_signing_identity="Arrowshot Local Signing"
fi
signing_identity="${ARROWSHOT_APP_SIGN_IDENTITY:-$default_signing_identity}"
architectures=(arm64 x86_64)

"$repository_root/Scripts/generate-app-icon.sh" >/dev/null
source_files=("$repository_root"/Sources/Arrowshot/**/*.swift)
architecture_binaries=()

for architecture in $architectures; do
    architecture_binary="$repository_root/.build/Arrowshot-$architecture"
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
for architecture in $architectures; do
    lipo "$binary_path" -verify_arch "$architecture"
done

if [[ -d "$application_directory" ]]; then
    rm -r "$application_directory"
fi

mkdir -p "$contents_directory/MacOS" "$contents_directory/Resources"
cp "$binary_path" "$contents_directory/MacOS/Arrowshot"
cp "$repository_root/Resources/Info.plist" "$contents_directory/Info.plist"
cp "$repository_root/Resources/Arrowshot.icns" "$contents_directory/Resources/Arrowshot.icns"
plutil -replace CFBundleIdentifier -string "$bundle_identifier" "$contents_directory/Info.plist"
xattr -cr "$application_directory"
codesign_flags=(--force --sign "$signing_identity")
# Hardened runtime + secure timestamp only for a real Developer ID identity,
# not for ad-hoc or the local self-signed cert (which has no trusted timestamp).
if [[ "$signing_identity" != "-" && "$signing_identity" != "Arrowshot Local Signing" ]]; then
    codesign_flags+=(--options runtime --timestamp)
fi
codesign $codesign_flags "$application_directory"
codesign --verify --deep --strict "$application_directory"

print "$application_directory"
