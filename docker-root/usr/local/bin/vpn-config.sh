#!/usr/bin/env bash
# aTrust-only runtime configuration. Evaluated by start.sh and start-sangfor.sh.
[[ "$(cat /etc/vpn-type 2>/dev/null)" == ATRUST ]] || {
  echo 'echo "aTrust is not installed" >&2; false'
  exit 0
}
cat <<'VPN'
_VPN_TYPE=ATRUST
SANGFOR_ROOT=/usr/share/sangfor
VPN_ROOT=$SANGFOR_ROOT/aTrust
VPN_RESOURCES=$VPN_ROOT/resources
VPN_BIN=$VPN_RESOURCES/bin
VPN_CONF=$VPN_RESOURCES/conf
VPN_UI=$VPN_ROOT/aTrustTray
VPN_TUN=utun7
FORCE_OPEN_PORTS=54631
VPN_PROCS=aTrustAgent
export VPN_ROOT VPN_RESOURCES VPN_BIN VPN_CONF VPN_TUN FORCE_OPEN_PORTS VPN_UI VPN_PROCS
vpn_daemon() {
  FAKE_LOGIN=sangfor LD_PRELOAD=/usr/local/lib/fake-getlogin.so \
      LD_LIBRARY_PATH="$VPN_ROOT:$VPN_BIN:${LD_LIBRARY_PATH:-}" \
      fake-hwaddr-run "$VPN_BIN/aTrustAgent" --plugin plugin-daemon --plugin-cmd '|' >/dev/null &
}
vpn_ui() {
  "$VPN_UI" --no-sandbox
}
VPN
