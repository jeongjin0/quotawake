#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
OUTPUT_DIR="${2:-${ROOT_DIR}/dist/cli}"

case "${CONFIGURATION}" in
  debug|release) ;;
  *)
    echo "usage: $0 [debug|release] [output-directory]" >&2
    exit 64
    ;;
esac

source "${ROOT_DIR}/version.env"
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid VERSION '${VERSION}'" >&2
  exit 65
fi

case "$(uname -s)" in
  Darwin) PLATFORM="macos" ;;
  Linux) PLATFORM="linux" ;;
  *)
    echo "Unsupported packaging host: $(uname -s)" >&2
    exit 66
    ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64|amd64) ARCH="x86_64" ;;
  *) ARCH="$(uname -m)" ;;
esac

cd "${ROOT_DIR}"
swift build -c "${CONFIGURATION}" --product quotawake
BIN_DIR="$(swift build -c "${CONFIGURATION}" --show-bin-path)"
ARGUMENT_PARSER_LICENSE="${ROOT_DIR}/.build/checkouts/swift-argument-parser/LICENSE.txt"
if [[ ! -s "${ARGUMENT_PARSER_LICENSE}" ]]; then
  echo "Missing swift-argument-parser license: ${ARGUMENT_PARSER_LICENSE}" >&2
  exit 67
fi

ARCHIVE_BASE="quotawake-${VERSION}-${PLATFORM}-${ARCH}"
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "${STAGE_DIR}"' EXIT
mkdir -p "${OUTPUT_DIR}" "${STAGE_DIR}/${ARCHIVE_BASE}"
cp "${BIN_DIR}/quotawake" "${STAGE_DIR}/${ARCHIVE_BASE}/quotawake"
cp LICENSE README.md "${STAGE_DIR}/${ARCHIVE_BASE}/"
cp Resources/THIRD_PARTY_NOTICES.md "${STAGE_DIR}/${ARCHIVE_BASE}/"
cp "${ARGUMENT_PARSER_LICENSE}" "${STAGE_DIR}/${ARCHIVE_BASE}/swift-argument-parser-LICENSE.txt"
chmod 755 "${STAGE_DIR}/${ARCHIVE_BASE}/quotawake"

tar -C "${STAGE_DIR}" -czf "${OUTPUT_DIR}/${ARCHIVE_BASE}.tar.gz" "${ARCHIVE_BASE}"
if command -v shasum >/dev/null 2>&1; then
  (cd "${OUTPUT_DIR}" && shasum -a 256 "${ARCHIVE_BASE}.tar.gz" > "${ARCHIVE_BASE}.tar.gz.sha256")
else
  (cd "${OUTPUT_DIR}" && sha256sum "${ARCHIVE_BASE}.tar.gz" > "${ARCHIVE_BASE}.tar.gz.sha256")
fi

echo "Created ${OUTPUT_DIR}/${ARCHIVE_BASE}.tar.gz"
