#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build
xcrun clang++ -std=c++23 -O2 -Wall -Wextra -Werror -Wno-missing-field-initializers -ICore -isystem Vendor/VirtualHID/vendor/vendor/include Tests/Core/engine_tests.cpp -o build/engine-tests
build/engine-tests
xcrun clang++ -std=c++23 -O2 -Wall -Wextra -Werror -ICore Tests/Core/transport_tests.cpp -o build/transport-tests
build/transport-tests
