#!/usr/bin/env zsh
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${VERSION:-1.0}"
BUILDS_DIR="${BUILDS_DIR:-Builds}"
ROOT="${BUILDS_DIR}/${VERSION}"
COMPONENT_PLIST="${ROOT}/component.plist"
UNSIGNED_PKG="${BUILDS_DIR}/mwav-phone-unsigned.pkg"
SIGNED_PKG="${BUILDS_DIR}/mwav-phone.pkg"

# One-time setup before this script will work end-to-end:
#
#   1. A "Developer ID Installer" cert for MWAV Pty Ltd must be in the
#      login keychain. Download from developer.apple.com if missing
#      (it is a separate cert from "Developer ID Application").
#
#   2. Store notarytool credentials once:
#        xcrun notarytool store-credentials mwav-notary \
#            --apple-id 1548@mwav.org \
#            --team-id M7988TBYF8 \
#            --password 
#
# Override either by exporting the env var before running this script.
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-Developer ID Installer: MWAV Pty Ltd (M7988TBYF8)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-mwav-notary}"

SOURCE_APP="${ROOT}/mwav-phone.app"
if [[ ! -d "${SOURCE_APP}" ]]; then
    echo "ERROR: ${SOURCE_APP} not found. Export the app from Xcode first." >&2
    exit 1
fi

# WorkDrive is a File Provider–backed sync mount, so the .app's bytes are
# not always materialized on disk — codesign/pkgbuild then fail with "host
# has no guest with the requested attributes". Stage to local disk first.
STAGE_DIR="$(mktemp -d -t mwav-phone-build)"
trap 'rm -rf "${STAGE_DIR}"' EXIT
echo "==> Staging app to ${STAGE_DIR} (forces File Provider to materialize)"
ditto "${SOURCE_APP}" "${STAGE_DIR}/mwav-phone.app"
xattr -cr "${STAGE_DIR}/mwav-phone.app"
STAGED_APP="${STAGE_DIR}/mwav-phone.app"

echo "==> Sanity-checking app signature"
codesign --verify --strict --verbose=2 "${STAGED_APP}"

echo "==> Building unsigned package"
pkgbuild --root "${STAGE_DIR}" \
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
