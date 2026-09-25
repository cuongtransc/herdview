#!/bin/sh
# Lets a Dock-launched Herdview drive cmux: switches cmux's socket to password
# mode with a fresh random password in ~/.config/cmux/cmux.json, then reloads
# cmux. The cmux CLI reads that password itself, so Herdview needs nothing more.
#
# cmux's default mode ("cmux processes only") admits only processes started
# inside a cmux terminal; an app opened from the Dock or Finder is refused.
#
# Safe to re-run: a file already in password mode is left alone, and a file
# whose `automation` block says something else is not rewritten — cmux.json is
# JSONC the person may have edited by hand.
set -eu

CMUX_JSON="${CMUX_JSON:-$HOME/.config/cmux/cmux.json}"
CMUX="${CMUX:-$(command -v cmux || echo /Applications/cmux.app/Contents/Resources/bin/cmux)}"

# Not `pgrep cmux`: macOS pgrep skips its own ancestors, and run from a cmux
# terminal cmux is one.
reload() {
  if [ -x "$CMUX" ] && "$CMUX" reload-config; then
    return
  fi
  echo "could not reload cmux; the setting takes effect when cmux next starts"
}

password="$(openssl rand -hex 24)"
block="  \"automation\": {
    \"socketControlMode\": \"password\",
    \"socketPassword\": \"$password\"
  },"

if [ ! -s "$CMUX_JSON" ]; then
  mkdir -p "$(dirname "$CMUX_JSON")"
  umask 077
  printf '{\n%s\n  "schemaVersion": 1\n}\n' "$block" > "$CMUX_JSON"
  echo "wrote $CMUX_JSON"
  reload
  exit 0
fi

# Only a live (uncommented) key counts; cmux's template carries the whole
# settings list commented out.
if grep -Eq '^[[:space:]]*"automation"[[:space:]]*:' "$CMUX_JSON"; then
  if grep -Eq '^[[:space:]]*"socketControlMode"[[:space:]]*:[[:space:]]*"password"' "$CMUX_JSON"; then
    echo "cmux is already in password mode ($CMUX_JSON)"
    exit 0
  fi
  echo "$CMUX_JSON already sets \"automation\"; set socketControlMode to \"password\" and a socketPassword there by hand, then run: cmux reload-config" >&2
  exit 1
fi

# The block goes first in the object, so its trailing comma always has a key
# after it; that needs the file to open with a bare `{` line and hold one key.
if [ "$(sed -n 1p "$CMUX_JSON" | tr -d '[:space:]')" != "{" ] ||
   ! grep -Eq '^[[:space:]]*"[^"]+"[[:space:]]*:' "$CMUX_JSON"; then
  echo "$CMUX_JSON does not open with a \"{\" line followed by settings; add the automation block by hand" >&2
  exit 1
fi

backup="$CMUX_JSON.bak-$(date +%Y%m%d-%H%M%S)"
cp -p "$CMUX_JSON" "$backup"
tmp="$(mktemp "$CMUX_JSON.XXXXXX")"
BLOCK="$block" awk 'NR == 1 { print; print ENVIRON["BLOCK"]; print ""; next } { print }' "$CMUX_JSON" > "$tmp"
[ "$(wc -l < "$tmp")" -gt "$(wc -l < "$CMUX_JSON")" ] || { rm -f "$tmp"; echo "edit produced nothing new; $CMUX_JSON left as it was" >&2; exit 1; }
chmod 600 "$tmp"
mv "$tmp" "$CMUX_JSON"
echo "password mode on in $CMUX_JSON (backup: $backup)"
reload
