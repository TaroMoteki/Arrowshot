#!/bin/zsh

set -euo pipefail

configuration="${1:-release}"
repository_root="${0:A:h:h}"
cd "$repository_root"

signing_configuration="${ARROWSHOT_SIGNING_CONFIG:-$repository_root/.release-signing.env}"
if [[ -f "$signing_configuration" ]]; then
    source "$signing_configuration"
fi

application_path="$repository_root/.build/Arrowshot.app"
installer_identity="${ARROWSHOT_INSTALLER_SIGN_IDENTITY:-}"

"$repository_root/Scripts/build-app.sh" "$configuration"

version="$(plutil -extract CFBundleShortVersionString raw "$application_path/Contents/Info.plist")"
bundle_identifier="$(plutil -extract CFBundleIdentifier raw "$application_path/Contents/Info.plist")"
package_path="$repository_root/.build/Arrowshot-$version.pkg"
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

ditto "$application_path" "$packaging_root/Arrowshot.app"
codesign --verify --deep --strict "$packaging_root/Arrowshot.app"

if [[ -f "$package_path" ]]; then
    rm "$package_path"
fi

package_flags=(
    --component "$packaging_root/Arrowshot.app"
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
codesign --verify --deep --strict "$validation_directory/Payload/Arrowshot.app"
rm -r "$validation_root"
validation_root=""

# pkgbuild can attach filesystem metadata to a source bundle while inspecting it.
# Re-sign the standalone build artifact so both the package payload and .app remain valid.
# Mirror build-app.sh: keep the stable local identity so TCC permissions survive.
default_application_identity="-"
if security find-identity -p codesigning 2>/dev/null | grep -q "Arrowshot Local Signing"; then
    default_application_identity="Arrowshot Local Signing"
fi
application_identity="${ARROWSHOT_APP_SIGN_IDENTITY:-$default_application_identity}"
application_signing_flags=(--force --sign "$application_identity")
if [[ "$application_identity" != "-" && "$application_identity" != "Arrowshot Local Signing" ]]; then
    application_signing_flags+=(--options runtime --timestamp)
fi
codesign $application_signing_flags "$application_path"
codesign --verify --deep --strict "$application_path"

trap - EXIT

print "$package_path"
