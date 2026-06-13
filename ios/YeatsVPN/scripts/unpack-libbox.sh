#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARCHIVE="${PROJECT_DIR}/YeatsVPN/Libbox.xcframework.zip"
FRAMEWORK="${PROJECT_DIR}/YeatsVPN/Libbox.xcframework"

if [[ -d "${FRAMEWORK}" ]]; then
  echo "Libbox.xcframework already exists: ${FRAMEWORK}"
  exit 0
fi

if [[ ! -f "${ARCHIVE}" ]]; then
  echo "Missing archive: ${ARCHIVE}" >&2
  exit 1
fi

echo "Unpacking Libbox.xcframework..."
ditto -x -k "${ARCHIVE}" "${PROJECT_DIR}/YeatsVPN"
echo "Done: ${FRAMEWORK}"
