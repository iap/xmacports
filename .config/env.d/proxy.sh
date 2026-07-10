#!/bin/bash
# Shadowsocks SOCKS5 proxy for outbound egress.
# Activates only when ss-local is listening on the configured port, so this
# file is safe on hosts without Shadowsocks (exports nothing).

set -u

if [[ -n "${DOTFILES_PROXY_LOADED:-}" ]]; then
  return 0
fi

# Shadowsocks local SOCKS5 endpoint (ss-local default port is 1080;
# this host runs it on 1086 — override in .profile.local if different).
PROXY_PORT="${SHADOWSOCKS_PORT:-1086}"
PROXY_HOST="${SHADOWSOCKS_HOST:-127.0.0.1}"
PROXY_URL="socks5://${PROXY_HOST}:${PROXY_PORT}"

# Only enable if the SOCKS listener is actually up.
_ss_up=0
if command -v lsof > /dev/null 2>&1; then
  lsof -iTCP:"${PROXY_PORT}" -sTCP:LISTEN -n -P > /dev/null 2>&1 && _ss_up=1
elif command -v nc > /dev/null 2>&1; then
  nc -z -w1 "${PROXY_HOST}" "${PROXY_PORT}" 2> /dev/null && _ss_up=1
fi

if [[ "$_ss_up" -eq 1 ]]; then
  export HTTP_PROXY="$PROXY_URL"
  export HTTPS_PROXY="$PROXY_URL"
  export ALL_PROXY="$PROXY_URL"
  export http_proxy="$PROXY_URL"
  export https_proxy="$PROXY_URL"
  export all_proxy="$PROXY_URL"
  # Keep localhost and the Hermes gateway off the proxy.
  export NO_PROXY="localhost,127.0.0.1,::1"
  export no_proxy="$NO_PROXY"
  export DOTFILES_PROXY_LOADED=1
fi

unset _ss_up PROXY_PORT PROXY_HOST PROXY_URL
