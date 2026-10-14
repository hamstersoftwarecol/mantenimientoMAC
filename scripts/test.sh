#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/module-cache
compiler_path="$(xcrun --find swiftc)"
developer_path="$(xcode-select -p)"
if [[ -d "${developer_path}/SDKs/MacOSX.sdk" ]]; then
  sdk_path="${developer_path}/SDKs/MacOSX.sdk"
else
  sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
fi
"${compiler_path}" -sdk "${sdk_path}" -swift-version 5 -module-cache-path build/module-cache Sources/Core.swift Sources/Inventory.swift Sources/Analysis.swift Sources/Cleaner.swift Sources/Uninstaller.swift Sources/BatchUninstaller.swift Tests/UninstallTests.swift Tests/BatchTests.swift Tests/main.swift -o build/tests
build/tests
