#!/bin/zsh

set -euo pipefail

configuration="${1:-release}"
repository_root="${0:A:h:h}"
cd "$repository_root"

signing_configuration="${PICTOJOT_SIGNING_CONFIG:-$repository_root/.release-signing.env}"
if [[ -f "$signing_configuration" ]]; then
    source "$signing_configuration"
fi

application_path="$repository_root/.build/PictoJot.app"
installer_identity="${PICTOJOT_INSTALLER_SIGN_IDENTITY:-}"

"$repository_root/Scripts/build-app.sh" "$configuration"

version="$(plutil -extract CFBundleShortVersionString raw "$application_path/Contents/Info.plist")"
bundle_identifier="$(plutil -extract CFBundleIdentifier raw "$application_path/Contents/Info.plist")"
package_path="$repository_root/.build/PictoJot-$version.pkg"
package_identifier="$bundle_identifier.pkg"
packaging_root="$(mktemp -d "$repository_root/.build/pkg-staging.XXXXXX")"
validation_root=""

cleanup_temporary_directories() {
    if [[ -n "$packaging_root" && -d "$packaging_root" ]]; then
        rm -r "$packaging_root"
    fi
    if [[ -n "$validation_root" && -d "$validation_root" ]]; then
        rm -r "$validation_root"
    fi
}
trap cleanup_temporary_directories EXIT

ditto "$application_path" "$packaging_root/PictoJot.app"
codesign --verify --deep --strict "$packaging_root/PictoJot.app"

if [[ -f "$package_path" ]]; then
    rm "$package_path"
fi

package_flags=(
    --component "$packaging_root/PictoJot.app"
    --install-location /Applications
    --scripts "$repository_root/Scripts/PackageScripts"
    --identifier "$package_identifier"
    --version "$version"
)
if [[ -n "$installer_identity" ]]; then
    package_flags+=(--sign "$installer_identity")
fi

COPYFILE_DISABLE=1 pkgbuild $package_flags "$package_path"
rm -r "$packaging_root"
packaging_root=""

if [[ -n "$installer_identity" ]]; then
    pkgutil --check-signature "$package_path"
else
    print "Created an unsigned installer package for local testing."
fi

validation_root="$(mktemp -d "$repository_root/.build/pkg-validation.XXXXXX")"
validation_directory="$validation_root/expanded"
pkgutil --expand-full "$package_path" "$validation_directory"
codesign --verify --deep --strict "$validation_directory/Payload/PictoJot.app"
rm -r "$validation_root"
validation_root=""

# pkgbuild can attach filesystem metadata to a source bundle while inspecting it.
# Re-sign the standalone build artifact so both the package payload and .app remain valid.
application_identity="${PICTOJOT_APP_SIGN_IDENTITY:--}"
application_signing_flags=(--force --sign "$application_identity")
if [[ "$application_identity" != "-" ]]; then
    application_signing_flags+=(--options runtime --timestamp)
fi
codesign $application_signing_flags "$application_path"
codesign --verify --deep --strict "$application_path"

trap - EXIT

print "$package_path"
