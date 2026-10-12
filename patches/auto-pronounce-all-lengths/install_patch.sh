#!/bin/bash
set -euo pipefail

# EasyDict Auto-Pronunciation Patch Installer
# Applies runtime audio unlock (words, phrases, sentences, paragraphs) to /Applications/Easydict.app

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="/Applications/Easydict.app"
BACKUP_PATH="/Applications/Easydict.app.original_backup"

echo "==> Checking EasyDict installation at ${APP_PATH}..."
if [ ! -d "${APP_PATH}" ]; then
    echo "Error: ${APP_PATH} not found. Please install EasyDict first."
    exit 1
fi

echo "==> Quitting running EasyDict instances..."
pkill -9 -f "Easydict" || true

echo "==> Creating backup if not already present..."
if [ ! -d "${BACKUP_PATH}" ]; then
    cp -R "${APP_PATH}" "${BACKUP_PATH}"
    echo "Backup created at ${BACKUP_PATH}"
else
    echo "Backup already exists at ${BACKUP_PATH}"
fi

echo "==> Compiling universal dylib (arm64 + x86_64)..."
clang -dynamiclib -arch arm64 -arch x86_64 \
    -fobjc-arc \
    -framework Foundation -framework AppKit -framework AVFoundation \
    -install_name @rpath/libeasydict_patch.dylib \
    "${SCRIPT_DIR}/libeasydict_patch.m" \
    -o "${SCRIPT_DIR}/libeasydict_patch.dylib"

echo "==> Copying dylib into App Frameworks..."
mkdir -p "${APP_PATH}/Contents/Frameworks"
cp -f "${SCRIPT_DIR}/libeasydict_patch.dylib" "${APP_PATH}/Contents/Frameworks/"

echo "==> Injecting dylib into Mach-O executable..."
python3 "${SCRIPT_DIR}/insert_dylib.py" \
    "@rpath/libeasydict_patch.dylib" \
    "${APP_PATH}/Contents/MacOS/Easydict"

echo "==> Re-signing application..."
xattr -cr "${APP_PATH}"
codesign --force --deep --sign - "${APP_PATH}"

echo "==> Resetting Accessibility TCC permissions..."
tccutil reset Accessibility com.izual.Easydict || true

echo "==> Launching patched EasyDict..."
open "${APP_PATH}"

echo "==> Patch installation completed successfully!"
