#!/usr/bin/env zsh
set -euo pipefail

cd "$(dirname "$0")"

# Archives the app, exports it signed with Developer ID, packages it, signs the
# package, notarizes and staples it. One command:
#
#   ./build-pkg.sh
#
# The package version is the app's MARKETING_VERSION unless VERSION is set.
# Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION first: component.plist has
# BundleIsVersionChecked, so the installer won't replace an installed copy
# that has a newer build number.

VERSION="${VERSION:-$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' Telephone.xcodeproj/project.pbxproj | head -1)}"
BUILDS_DIR="${BUILDS_DIR:-Builds}"
COMPONENT_PLIST="component.plist"
EXPORT_OPTIONS="ExportOptions.plist"
UNSIGNED_PKG="${BUILDS_DIR}/mwav-phone-${VERSION}-unsigned.pkg"
SIGNED_PKG="${BUILDS_DIR}/mwav-phone-${VERSION}.pkg"

# One-time setup before this script will work end-to-end:
#
#   1. "Developer ID Application" and "Developer ID Installer" certs for
#      MWAV Pty Ltd must be in the login keychain. Download from
#      developer.apple.com if missing (they are separate certs).
#
#   2. Store notarytool credentials once:
#        xcrun notarytool store-credentials mwav-notary \
#            --apple-id 1548@mwav.org \
#            --team-id M7988TBYF8 \
#            --password
#
#   3. Telephone/CallerID.local.xcconfig must hold MWAV_CALLER_ID_KEY (see
#      Telephone/CallerID.xcconfig). The build refuses to package without it.
#
# Override either identity/profile by exporting the env var before running this script.
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-Developer ID Installer: MWAV Pty Ltd (M7988TBYF8)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-mwav-notary}"

mkdir -p "${BUILDS_DIR}"

# WorkDrive is a File Provider–backed sync mount, so a bundle's bytes are
# not always materialized on disk — codesign/pkgbuild then fail with "host
# has no guest with the requested attributes". Build and stage on local disk.
STAGE_DIR="$(mktemp -d -t mwav-phone-build)"
trap 'rm -rf "${STAGE_DIR}"' EXIT
ARCHIVE="${STAGE_DIR}/mwav-phone.xcarchive"
EXPORT_DIR="${STAGE_DIR}/export"
PKG_ROOT="${STAGE_DIR}/root"

echo "==> Archiving mwav-phone ${VERSION} (Release)"
xcodebuild archive \
    -project Telephone.xcodeproj \
    -scheme Telephone \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "${ARCHIVE}" \
    -allowProvisioningUpdates \
    -quiet

echo "==> Exporting with Developer ID"
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE}" \
    -exportPath "${EXPORT_DIR}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}" \
    -allowProvisioningUpdates \
    -quiet

STAGED_APP="${PKG_ROOT}/mwav-phone.app"
mkdir -p "${PKG_ROOT}"
ditto "${EXPORT_DIR}/mwav-phone.app" "${STAGED_APP}"
xattr -cr "${STAGED_APP}"

echo "==> Checking the caller ID key is built in"
CALLER_ID_KEY="$(/usr/libexec/PlistBuddy -c 'Print :MWAVCallerIDKey' "${STAGED_APP}/Contents/Info.plist" 2>/dev/null || true)"
if [[ -z "${CALLER_ID_KEY}" ]]; then
    echo "ERROR: MWAVCallerIDKey is empty, so this build would never report calls." >&2
    echo "       Set MWAV_CALLER_ID_KEY in Telephone/CallerID.local.xcconfig." >&2
    exit 1
fi

echo "==> Sanity-checking app signature"
codesign --verify --strict --verbose=2 "${STAGED_APP}"

echo "==> Building unsigned package"
pkgbuild --root "${PKG_ROOT}" \
    --component-plist "${COMPONENT_PLIST}" \
    --install-location /Applications \
    --version "${VERSION}" \
    "${UNSIGNED_PKG}"

echo "==> Signing package as ${INSTALLER_IDENTITY}"
productsign --sign "${INSTALLER_IDENTITY}" "${UNSIGNED_PKG}" "${SIGNED_PKG}"
rm -f "${UNSIGNED_PKG}"

echo "==> Verifying package signature"
pkgutil --check-signature "${SIGNED_PKG}"

echo "==> Submitting to Apple notary service (this can take a few minutes)"
xcrun notarytool submit "${SIGNED_PKG}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "${SIGNED_PKG}"

echo "==> Final validation"
xcrun stapler validate "${SIGNED_PKG}"
spctl --assess --type install -vv "${SIGNED_PKG}" || true

echo
echo "Done: $(pwd)/${SIGNED_PKG}"
