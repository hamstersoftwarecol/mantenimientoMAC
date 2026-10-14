#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
bundle="${PWD}/Mantenimiento Mac.app"
mkdir -p build/module-cache "${bundle}/Contents/MacOS" "${bundle}/Contents/Resources"
compiler_path="$(xcrun --find swiftc)"
developer_path="$(xcode-select -p)"
if [[ -d "${developer_path}/SDKs/MacOSX.sdk" ]]; then
  sdk_path="${developer_path}/SDKs/MacOSX.sdk"
else
  sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
fi
"${compiler_path}" -sdk "${sdk_path}" -swift-version 5 -O -target arm64-apple-macos13.0 -module-cache-path build/module-cache Sources/Core.swift Sources/Inventory.swift Sources/Analysis.swift Sources/Cleaner.swift Sources/Uninstaller.swift Sources/BatchUninstaller.swift Sources/UninstallReviewView.swift Sources/App.swift -o "${bundle}/Contents/MacOS/MantenimientoMac"
cp Resources/Info.plist "${bundle}/Contents/Info.plist"
codesign --force --sign - "${bundle}"
codesign --verify --strict "${bundle}"
print "Aplicación compilada: ${bundle}"
