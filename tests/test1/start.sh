#!/usr/bin/env bash
set -euo pipefail

ADDR="127.0.0.1"

run_gnome() {
  local title="$1"
  shift
  local cmd="$*"
  gnome-terminal --title="$title" -- bash -lc "$cmd; exec bash" >/dev/null 2>&1 &
}

echo "Uruchomienie serwerow (wartosci liczbowe)..."

# ===== SERWERY (NUMERIC VALUES) =====

# WAW
run_gnome "S1-TCP google:16001"  "java TCPServer -port 16001 -key google    -value 101"
run_gnome "S2-UDP apple:16002"   "java UDPServer -port 16002 -key apple     -value 102"

# WAW-B1
run_gnome "S3-UDP microsoft:16003" "java UDPServer -port 16003 -key microsoft -value 103"
run_gnome "S4-TCP mozilla:16004"   "java TCPServer -port 16004 -key mozilla   -value 104"

# KRK-A
run_gnome "S5-TCP opera:16005"   "java TCPServer -port 16005 -key opera     -value 105"
run_gnome "S6-UDP amazon:16006"  "java UDPServer -port 16006 -key amazon    -value 106"
run_gnome "S7-TCP youtube:16007" "java TCPServer -port 16007 -key youtube   -value 107"

# GDN
run_gnome "S8-UDP facebook:16008" "java UDPServer -port 16008 -key facebook  -value 108"
run_gnome "S9-TCP twitter:16009"  "java TCPServer -port 16009 -key twitter   -value 109"
run_gnome "S10-UDP netflix:16010" "java UDPServer -port 16010 -key netflix   -value 110"
run_gnome "S11-TCP example:16011" "java TCPServer -port 16011 -key example   -value 111"

sleep 1
echo "Start proxy (od lisci do roota)..."

# ===== PROXY (od liści do roota) =====

echo "Proxy - lisci"
run_gnome "P2-waw-a:15011"  "java Proxy -port 15011 -server $ADDR 16001 -server $ADDR 16002"
run_gnome "P3-waw-b1:15013" "java Proxy -port 15013 -server $ADDR 16003 -server $ADDR 16004"
run_gnome "P3-krk-a1:15022" "java Proxy -port 15022 -server $ADDR 16007"
run_gnome "P3-gdn-a1:15032" "java Proxy -port 15032 -server $ADDR 16009 -server $ADDR 16010"

sleep 1
echo "Proxy - srodek"
run_gnome "P2-waw-b:15012"  "java Proxy -port 15012 -server $ADDR 15013"
run_gnome "P2-krk-a:15021"  "java Proxy -port 15021 -server $ADDR 16005 -server $ADDR 16006 -server $ADDR 15022"
run_gnome "P2-gdn-a:15031"  "java Proxy -port 15031 -server $ADDR 15032 -server $ADDR 16011"

sleep 1
echo "Proxy - poziom P1"
run_gnome "P1-waw:15010" "java Proxy -port 15010 -server $ADDR 15011 -server $ADDR 15012"
run_gnome "P1-krk:15020" "java Proxy -port 15020 -server $ADDR 15021"
run_gnome "P1-gdn:15030" "java Proxy -port 15030 -server $ADDR 16008 -server $ADDR 15031"

sleep 1
echo "Proxy - ROOT"
run_gnome "P0-root:15000" "java Proxy -port 15000 -server $ADDR 15010 -server $ADDR 15020 -server $ADDR 15030"

echo "Gotowe."
