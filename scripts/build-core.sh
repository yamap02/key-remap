#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build
headers="$PWD/Vendor/VirtualHID/vendor/vendor/include"
xcrun clang++ -std=c++23 -O2 -Wall -Wextra -Wno-missing-field-initializers -fobjc-arc -ICore -isystem "$headers" Core/core.mm -framework Foundation -framework Security -framework IOKit -framework SystemConfiguration -framework Carbon -o build/rekey-core
xcrun clang++ -std=c++23 -O2 -Wall -Wextra -ICore -isystem "$headers" -isystem Vendor/VirtualHID/include Core/vhid.cpp -framework IOKit -framework CoreFoundation -o build/rekey-vhid
xcrun clang++ -std=c++23 -O2 -Wall -Wextra -Werror -Wno-missing-field-initializers -ICore -isystem "$headers" Core/bench.cpp -o build/rekey-bench
