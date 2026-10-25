#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build
xcrun clang++ -std=c++23 -O2 -Wall -Wextra -Werror -Wno-missing-field-initializers -ICore -isystem Vendor/VirtualHID/vendor/vendor/include Tests/Core/engine_tests.cpp -o build/engine-tests
build/engine-tests
xcrun clang++ -std=c++23 -O2 -Wall -Wextra -Werror -ICore -isystem Vendor/VirtualHID/include -isystem Vendor/VirtualHID/vendor/vendor/include Tests/Core/output_tests.cpp -o build/output-tests
build/output-tests
xcrun clang++ -std=c++23 -O2 -Wall -Wextra -Werror -ICore -isystem Vendor/VirtualHID/include -isystem Vendor/VirtualHID/vendor/vendor/include Tests/Core/output_lifecycle_tests.cpp -framework IOKit -framework CoreFoundation -o build/output-lifecycle-tests
build/output-lifecycle-tests
