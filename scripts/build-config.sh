#!/bin/zsh
# Sourced by the build scripts. Identifiers are deliberately restricted so
# they are safe both in code requirements and compiler/plist arguments.
REKEY_PRODUCT_ID="${REKEY_PRODUCT_ID:-jp.example.rekey}"
if [[ ! "$REKEY_PRODUCT_ID" =~ '^[A-Za-z0-9]+([.-][A-Za-z0-9]+)*[.][A-Za-z0-9]+([.-][A-Za-z0-9]+)*$' ]]; then
  echo 'REKEY_PRODUCT_ID must be a dotted bundle identifier using letters, digits and hyphens' >&2
  exit 64
fi
# Leave room for service suffixes within launchd's Mach name limit.
if (( ${#REKEY_PRODUCT_ID} > 120 )); then
  echo 'REKEY_PRODUCT_ID is too long for service names' >&2; exit 64
fi
if [[ -n "${REKEY_TEAM_ID:-}" ]]; then
  if [[ ! "$REKEY_TEAM_ID" =~ '^[A-Z0-9]{10}$' ]]; then echo 'REKEY_TEAM_ID must be a 10-character Team ID' >&2; exit 64; fi
  if [[ -z "${REKEY_SIGNING_IDENTITY:-}" || "$REKEY_SIGNING_IDENTITY" == '-' ]]; then
    echo 'REKEY_TEAM_ID requires a non-ad-hoc application signing identity' >&2; exit 64
  fi
fi
export REKEY_PRODUCT_ID

# Distribution is an explicit mode; development builds may remain ad-hoc.
REKEY_RELEASE="${REKEY_RELEASE:-0}"
case "$REKEY_RELEASE" in 0|1) ;; *) echo 'REKEY_RELEASE must be 0 or 1' >&2; exit 64;; esac
REKEY_DEVELOPMENT_DISTRIBUTION="${REKEY_DEVELOPMENT_DISTRIBUTION:-0}"
case "$REKEY_DEVELOPMENT_DISTRIBUTION" in 0|1) ;; *) echo 'REKEY_DEVELOPMENT_DISTRIBUTION must be 0 or 1' >&2; exit 64;; esac
if [[ "$REKEY_DEVELOPMENT_DISTRIBUTION" == 1 ]]; then
  [[ "$REKEY_RELEASE" == 0 ]] || { echo 'Development distribution cannot use release signing mode' >&2; exit 64; }
  for name in REKEY_TEAM_ID REKEY_INSTALLER_IDENTITY REKEY_NOTARY_PROFILE; do
    [[ -z "${(P)name:-}" ]] || { echo "$name must be unset for unnotarized development distribution" >&2; exit 64; }
  done
  [[ "${REKEY_SIGNING_IDENTITY:--}" == '-' ]] || { echo 'Development distribution requires ad-hoc signing' >&2; exit 64; }
fi
if [[ "$REKEY_RELEASE" == 1 || "$REKEY_DEVELOPMENT_DISTRIBUTION" == 1 ]]; then
  required=(REKEY_PRODUCT_ID REKEY_VERSION REKEY_BUILD_NUMBER REKEY_FEED_URL REKEY_ED_PUBLIC_KEY)
  if [[ "$REKEY_RELEASE" == 1 ]]; then required+=(REKEY_TEAM_ID REKEY_SIGNING_IDENTITY); fi
  for name in "${required[@]}"; do
    if [[ -z "${(P)name:-}" ]]; then echo "$name is required for a release build" >&2; exit 64; fi
  done
  if [[ "$REKEY_PRODUCT_ID" == jp.example.* || "$REKEY_PRODUCT_ID" == com.example.* || "$REKEY_PRODUCT_ID" == org.example.* ]]; then
    echo 'A release build requires a real product identifier' >&2; exit 64
  fi
  if [[ ! "$REKEY_VERSION" =~ '^[0-9]+([.][0-9]+){1,2}$' ]]; then
    echo 'REKEY_VERSION must be a numeric dotted version' >&2; exit 64
  fi
  if [[ ! "$REKEY_BUILD_NUMBER" =~ '^[1-9][0-9]*$' ]]; then
    echo 'REKEY_BUILD_NUMBER must be a positive integer without leading zeros' >&2; exit 64
  fi
  /usr/bin/python3 - "$REKEY_FEED_URL" "$REKEY_ED_PUBLIC_KEY" <<'PYTHON' || exit 64
import base64, binascii, ipaddress, sys, urllib.parse
u = urllib.parse.urlsplit(sys.argv[1])
host = (u.hostname or '').lower().rstrip('.')
try:
    ipaddress.ip_address(host)
except ValueError:
    ip = False
else:
    ip = True
if (u.scheme != 'https' or not host or ip or u.username or u.password or
        host in ('localhost', 'example.com', 'example.net', 'example.org') or
        host.endswith(('.localhost', '.invalid', '.example', '.test', '.example.com', '.example.net', '.example.org'))):
    sys.exit('A release requires a non-placeholder HTTPS feed URL')
try:
    key = base64.b64decode(sys.argv[2], validate=True)
except (ValueError, binascii.Error):
    sys.exit('A release requires a valid EdDSA public key')
if len(key) != 32:
    sys.exit('A release requires a valid EdDSA public key')
PYTHON
fi
export REKEY_RELEASE REKEY_DEVELOPMENT_DISTRIBUTION
