# Third-party notices

ReKey includes third-party software. The following notices and accompanying
license texts apply to components used by this build. Sparkle's license file
also includes notices for software bundled by Sparkle.

- Sparkle 2.9.6: `Sparkle.txt` (MIT and included external licenses).
- Karabiner-DriverKit-VirtualHIDDevice client: `Karabiner-DriverKit-VirtualHIDDevice.txt` (Unlicense). Its separately installed official driver package has its own notices.
- Asio 1.38.2: `Boost-Software-License-1.0.txt`; copyright 2003–2026 Christopher M. Kohlhoff, 2005 Stefan Arentz, 2008 Rep Invariant Systems, Inc., 2011 Boris Schaeling, 2014 Oliver Kowalke, and 2021 Klemens D. Morgenstern.
- pqrs C++ headers including dispatcher, HID, GSL and unix-domain-stream: `Boost-Software-License-1.0.txt`; copyright 2018–2026 Takayama Fumihiko.
- Microsoft Guidelines Support Library: `Microsoft-GSL.txt`; copyright 2015 and 2026 Microsoft Corporation.
- nlohmann/json 3.12.0: `nlohmann-json.txt`; copyright 2013–2025 Niels Lohmann. Included source files also credit 2008–2009 Björn Hoehrmann, 2009 Florian Loitsch, 2016–2021 Evan Nemerson, and 2018 The Abseil Authors; their included contributions carry the MIT identifier in the vendored headers.
- nod: `nod.txt`; copyright 2015 Fredrik Berggren.
- type_safe: `type_safe.txt`; copyright 2016–2020 Jonathan Müller.

License texts were obtained from the component projects. For traceability:

- <https://github.com/chriskohlhoff/asio/blob/8806a6803cde7054c3049d3666d3ec36786568c5/LICENSE_1_0.txt>
- <https://github.com/microsoft/GSL/blob/a4651c0f995d3309432f78e977058d9d4760f9fa/LICENSE>
- <https://github.com/nlohmann/json/blob/v3.12.0/LICENSE.MIT>
- <https://github.com/fr00b0/nod/blob/23e4190f3d15964dd1f00677120a788824d74ec9/LICENSE>
- <https://github.com/foonathan/type_safe/blob/292e8c127037e33d92f8f52dab0f1184993942d0/LICENSE>

On 2026-11-07, all 1,147 tracked files under `Vendor/VirtualHID` matched the
Git blob IDs in upstream commit `ac836ed8a974cd5182495251855cabdb762f50cb`.
All 912 files in its nested `vendor/vendor/include` directory were tracked.
That establishes the upstream snapshot, not the original revision of each
third-party component or the completeness of its notices. Repeat the
dependency and license audit when dependencies or build flags change.
