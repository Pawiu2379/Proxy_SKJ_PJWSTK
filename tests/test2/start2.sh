#!/usr/bin/env bash
set -euo pipefail
ADDR="127.0.0.1"

run_gnome() {
  local title="$1"; shift
  gnome-terminal --title="$title" -- bash -lc "$*; exec bash" >/dev/null 2>&1 &
}

# ===== SERWERY =====
run_gnome "S1 TCP dns:16101"     "java TCPServer -port 16101 -key dns     -value 301"
run_gnome "S2 UDP ntp:16102"     "java UDPServer -port 16102 -key ntp     -value 302"
run_gnome "S3 UDP git:16103"     "java UDPServer -port 16103 -key git     -value 303"
run_gnome "S4 TCP mail:16104"    "java TCPServer -port 16104 -key mail    -value 304"
run_gnome "S5 UDP snmp:16105"    "java UDPServer -port 16105 -key snmp    -value 305"
run_gnome "S6 UDP weather:16106" "java UDPServer -port 16106 -key weather -value 306"
run_gnome "S7 TCP search:16107"  "java TCPServer -port 16107 -key search  -value 307"
run_gnome "S8 TCP video:16108"   "java TCPServer -port 16108 -key video   -value 308"
run_gnome "S9 UDP docs:16109"    "java UDPServer -port 16109 -key docs    -value 309"
run_gnome "S10 UDP chat:16110"   "java UDPServer -port 16110 -key chat    -value 310"
run_gnome "S11 TCP maps:16111"   "java TCPServer -port 16111 -key maps    -value 311"
run_gnome "S12 UDP music:16112"  "java UDPServer -port 16112 -key music   -value 312"
run_gnome "S13 TCP store:16113"  "java TCPServer -port 16113 -key store   -value 313"
run_gnome "S14 UDP auth:16114"   "java UDPServer -port 16114 -key auth    -value 314"

sleep 1

# ===== PROXY (od liści do roota) =====
# najgłębiej
run_gnome "P4 gdn-a2-1:15134" "java Proxy -port 15134 -server $ADDR 16113 -server $ADDR 16114"
sleep 1
run_gnome "P3 gdn-a2:15133"  "java Proxy -port 15133 -server $ADDR 15134"
run_gnome "P3 gdn-a1:15132"  "java Proxy -port 15132 -server $ADDR 16111 -server $ADDR 16112"
run_gnome "P3 krk-a1:15122"  "java Proxy -port 15122 -server $ADDR 16108 -server $ADDR 16109"
run_gnome "P3 waw-a1:15114"  "java Proxy -port 15114 -server $ADDR 16103"

sleep 1
run_gnome "P2 gdn-a:15131"   "java Proxy -port 15131 -server $ADDR 15132 -server $ADDR 15133"
run_gnome "P2 krk-a:15121"   "java Proxy -port 15121 -server $ADDR 16106 -server $ADDR 16107 -server $ADDR 15122"
run_gnome "P2 waw-a:15111"   "java Proxy -port 15111 -server $ADDR 16101 -server $ADDR 16102 -server $ADDR 15114"
run_gnome "P2 waw-b:15112"   "java Proxy -port 15112 -server $ADDR 16104 -server $ADDR 16105"

sleep 1
run_gnome "P1 gdn:15130"     "java Proxy -port 15130 -server $ADDR 16110 -server $ADDR 15131"
run_gnome "P1 krk:15120"     "java Proxy -port 15120 -server $ADDR 15121"
run_gnome "P1 waw:15110"     "java Proxy -port 15110 -server $ADDR 15111 -server $ADDR 15112"

sleep 1
run_gnome "P0 core:15100"    "java Proxy -port 15100 -server $ADDR 15110 -server $ADDR 15120 -server $ADDR 15130"

echo "OK: siec NUMERLAND v2 uruchomiona."
