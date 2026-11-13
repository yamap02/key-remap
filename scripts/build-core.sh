#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/build-config.sh
mkdir -p build
xcrun clang++ -std=c++23 -O2 -Wall -Wextra -Werror -Wno-missing-field-initializers -fobjc-arc "-DREKEY_PRODUCT_ID=\"${REKEY_PRODUCT_ID}\"" -ICore -isystem Vendor/VirtualHID/vendor/vendor/include -isystem Vendor/VirtualHID/include Core/core.mm -framework Foundation -framework Security -framework IOKit -framework SystemConfiguration -framework Carbon -o build/rekey-core
xcrun clang++ -std=c++23 -O2 -Wall -Wextra -Werror -Wno-missing-field-initializers -ICore -isystem Vendor/VirtualHID/vendor/vendor/include Core/bench.cpp -o build/rekey-bench
