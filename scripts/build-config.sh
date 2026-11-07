#!/bin/zsh
# Sourced by the build scripts. Identifiers are deliberately restricted so
# they are safe both in code requirements and compiler/plist arguments.
REKEY_PRODUCT_ID="${REKEY_PRODUCT_ID:-jp.example.rekey}"
if [[ ! "$REKEY_PRODUCT_ID" =~ '^[A-Za-z0-9]+([.-][A-Za-z0-9]+)*[.][A-Za-z0-9]+([.-][A-Za-z0-9]+)*$' ]]; then
  echo 'REKEY_PRODUCT_ID must be a dotted bundle identifier using letters, digits and hyphens' >&2
  exit 64
fi
if [[ -n "${REKEY_TEAM_ID:-}" ]]; then
  if [[ ! "$REKEY_TEAM_ID" =~ '^[A-Z0-9]{10}$' ]]; then echo 'REKEY_TEAM_ID must be a 10-character Team ID' >&2; exit 64; fi
  if [[ -z "${REKEY_SIGNING_IDENTITY:-}" || "$REKEY_SIGNING_IDENTITY" == '-' ]]; then
    echo 'REKEY_TEAM_ID requires a non-ad-hoc application signing identity' >&2; exit 64
  fi
fi
export REKEY_PRODUCT_ID
