#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# proxy_test_numerland_v2.sh
# Wymaganie: siec NUMERLAND v2 jest juz uruchomiona.
#
# Architektura (porty proxy):
# P0-core=15100
# WAW: P1=15110, P2-a=15111, P2-b=15112, P3-a1=15114
# KRK: P1=15120, P2-a=15121, P3-a1=15122
# GDN: P1=15130, P2-a=15131, P3-a1=15132, P3-a2=15133, P4-a2-1=15134
#
# Klucze globalne (14):
# dns ntp git mail snmp weather search video docs chat maps music store auth
# ============================================================

ADDR="127.0.0.1"
DELAY=1

# ---- proxy ports ----
P0=15100

P1_WAW=15110
P2_WAW_A=15111
P2_WAW_B=15112
P3_WAW_A1=15114

P1_KRK=15120
P2_KRK_A=15121
P3_KRK_A1=15122

P1_GDN=15130
P2_GDN_A=15131
P3_GDN_A1=15132
P3_GDN_A2=15133
P4_GDN_A2_1=15134

# ---- expected global keys + values ----
EXPECTED_KEYS=(dns ntp git mail snmp weather search video docs chat maps music store auth)
declare -A VAL=(
  [dns]=301
  [ntp]=302
  [git]=303
  [mail]=304
  [snmp]=305
  [weather]=306
  [search]=307
  [video]=308
  [docs]=309
  [chat]=310
  [maps]=311
  [music]=312
  [store]=313
  [auth]=314
)

# ---------- helpers ----------
hr() { echo "============================================================"; }
blank() { echo; }

last_nonempty_line() {
  awk 'NF{last=$0} END{print last}'
}

tcp_raw() {
  local port="$1"; shift
  # Example: tcp_raw 15100 GET NAMES
  java TCPClient -address "$ADDR" -port "$port" -command "$@" 2>&1 | last_nonempty_line
}

udp_raw() {
  local port="$1"; shift
  java UDPClient -address "$ADDR" -port "$port" -command "$@" 2>&1 | last_nonempty_line
}

die() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS"
}

sleep_step() { sleep "$DELAY"; }

expect_prefix() {
  local got="$1"
  local prefix="$2"
  [[ "$got" == "$prefix"* ]] || die "Oczekiwano prefixu '$prefix', dostano: $got"
}

expect_equals() {
  local got="$1"
  local exp="$2"
  [[ "$got" == "$exp" ]] || die "Oczekiwano: '$exp'  |  Dostano: '$got'"
}

sorted_words() {
  # prints sorted words from arguments
  printf "%s\n" "$@" | sort | tr '\n' ' ' | sed 's/ $//'
}

expect_get_names() {
  local proto="$1" port="$2" expected_count="$3"

  local line
  if [[ "$proto" == "TCP" ]]; then
    line="$(tcp_raw "$port" GET NAMES)"
  else
    line="$(udp_raw "$port" GET NAMES)"
  fi

  echo "  -> $proto @ $port : $line"
  expect_prefix "$line" "OK "

  read -ra tok <<< "$line"
  [[ "${#tok[@]}" -ge 3 ]] || die "GET NAMES: za malo tokenow: $line"

  local count="${tok[1]}"
  [[ "$count" =~ ^[0-9]+$ ]] || die "GET NAMES: licznik nie jest liczba: '$count' w linii: $line"
  [[ "$count" -eq "$expected_count" ]] || die "GET NAMES: zly licznik. Expected=$expected_count got=$count | $line"

  local got_names=("${tok[@]:2}")
  local got_sorted exp_sorted
  got_sorted="$(sorted_words "${got_names[@]}")"
  exp_sorted="$(sorted_words "${EXPECTED_KEYS[@]}")"

  [[ "$got_sorted" == "$exp_sorted" ]] || die "GET NAMES: lista nazw nie pasuje.\nExpected: $exp_sorted\nGot:      $got_sorted"
  pass
}

expect_get_value() {
  local proto="$1" port="$2" key="$3" exp_val="$4"

  local line
  if [[ "$proto" == "TCP" ]]; then
    line="$(tcp_raw "$port" GET VALUE "$key")"
  else
    line="$(udp_raw "$port" GET VALUE "$key")"
  fi

  echo "  -> $proto @ $port : $line"
  expect_equals "$line" "OK $exp_val"
  pass
}

expect_set_ok() {
  local proto="$1" port="$2" key="$3" new_val="$4"

  local line
  if [[ "$proto" == "TCP" ]]; then
    line="$(tcp_raw "$port" SET "$key" "$new_val")"
  else
    line="$(udp_raw "$port" SET "$key" "$new_val")"
  fi

  echo "  -> $proto @ $port : $line"
  expect_equals "$line" "OK"
  pass
}

expect_na() {
  local proto="$1" port="$2" what="$3" key="$4"

  local line
  if [[ "$proto" == "TCP" ]]; then
    line="$(tcp_raw "$port" "$what" "$key")"
  else
    line="$(udp_raw "$port" "$what" "$key")"
  fi

  echo "  -> $proto @ $port : $line"
  expect_equals "$line" "NA"
  pass
}

title() {
  hr
  echo "$1"
  hr
}

# ============================================================
# TESTY
# ============================================================

title "TEST 0 (PREREQ): Czy dzialaja serwery (bez proxy) – szybki sanity check"
echo "Co testuje:"
echo "  - Czy serwery odpowiadaja zgodnie z protokolem (OK/NA)"
echo "Komendy (przyklad):"
echo "  - TCPServer(dns) 16101, UDPServer(ntp) 16102"
echo

echo "- GET VALUE dns bezposrednio (TCP 16101)"
echo "  -> $(tcp_raw 16101 GET VALUE dns)"
sleep_step
echo "- GET VALUE ntp bezposrednio (UDP 16102)"
echo "  -> $(udp_raw 16102 GET VALUE ntp)"
sleep_step
echo "OK (prereq)\n"

# ------------------------------------------------------------

title "TEST 1 (150/300): Proxy otwiera porty i obsluguje GET NAMES (TCP i UDP) – licznik + lista"
echo "Co testuje:"
echo "  - Czy kazdy proxy przyjmuje klienta TCP i UDP (porty otwarte)"
echo "  - Czy GET NAMES zwraca OK <liczba> <nazwy...> z poprawnym licznikiem"
echo "Komendy:"
echo

for p in "$P0" "$P1_WAW" "$P2_WAW_B" "$P3_KRK_A1" "$P4_GDN_A2_1"; do
  echo "- GET NAMES na proxy $p (TCP)"
  expect_get_names TCP "$p" 14
  sleep_step
  echo "- GET NAMES na proxy $p (UDP)"
  expect_get_names UDP "$p" 14
  sleep_step
  blank
done

# ------------------------------------------------------------

title "TEST 2 (300): Proxy<->Serwery, mostkowanie protokolow (TCPClient<->UDPServer i UDPClient<->TCPServer)"
echo "Co testuje:"
echo "  - Czy proxy potrafi obsluzyc klienta w innym protokole niz serwer klucza"
echo "  - Minimalnie: routing do serwerow bez koniecznosci proxy->proxy"
echo "Komendy:"
echo

echo "- TCPClient do P2-waw-b -> klucz snmp (snmp jest na UDPServer)"
expect_get_value TCP "$P2_WAW_B" snmp "${VAL[snmp]}"
sleep_step

echo "- UDPClient do P2-waw-b -> klucz mail (mail jest na TCPServer)"
expect_get_value UDP "$P2_WAW_B" mail "${VAL[mail]}"
sleep_step

echo "- TCPClient do P3-gdn-a1 -> klucz music (UDPServer)"
expect_get_value TCP "$P3_GDN_A1" music "${VAL[music]}"
sleep_step

echo "- UDPClient do P3-gdn-a1 -> klucz maps (TCPServer)"
expect_get_value UDP "$P3_GDN_A1" maps "${VAL[maps]}"
sleep_step

# ------------------------------------------------------------

title "TEST 3 (400): Routing po drzewie (w gore / w bok / w dol) – klucze z innych galezi"
echo "Co testuje:"
echo "  - Czy proxy->proxy przekazuje zapytania w strukturze drzewa (bez cykli)"
echo "  - Wejscie na roznych poziomach drzewa i pytania o klucze z innych galezi"
echo "Komendy:"
echo

echo "- Wejscie nisko (P2-waw-a) -> pytanie o auth (gleboko w GDN, UDP)"
expect_get_value TCP "$P2_WAW_A" auth "${VAL[auth]}"
sleep_step

echo "- Wejscie nisko (P3-waw-a1) -> pytanie o weather (KRK, UDP)"
expect_get_value UDP "$P3_WAW_A1" weather "${VAL[weather]}"
sleep_step

echo "- Wejscie na P1 (P1-krk) -> pytanie o git (WAW, UDP)"
expect_get_value TCP "$P1_KRK" git "${VAL[git]}"
sleep_step

echo "- Wejscie na P1 (P1-gdn) -> pytanie o search (KRK, TCP)"
expect_get_value UDP "$P1_GDN" search "${VAL[search]}"
sleep_step

echo "- Wejscie bardzo gleboko (P4-gdn-a2-1) -> pytanie o dns (WAW, TCP)"
expect_get_value TCP "$P4_GDN_A2_1" dns "${VAL[dns]}"
sleep_step

echo "- Wejscie w ROOT (P0) -> pytanie o video (KRK, TCP) oraz chat (GDN, UDP)"
expect_get_value TCP "$P0" video "${VAL[video]}"
sleep_step
expect_get_value UDP "$P0" chat "${VAL[chat]}"
sleep_step

# ------------------------------------------------------------

title "TEST 4 (400): SET przez rozne protokoly + weryfikacja z innej galezi"
echo "Co testuje:"
echo "  - Czy SET dociera do wlasciwego serwera (po wielu proxy)"
echo "  - Czy odczyt z innej galezi widzi nowa wartosc"
echo "Komendy:"
echo

echo "- SET store=9001 (store jest TCP, a klient UDP wchodzi w WAW) -> potem GET z KRK"
expect_set_ok UDP "$P2_WAW_B" store 9001
sleep_step
expect_get_value TCP "$P1_KRK" store 9001
sleep_step

echo "- SET auth=8123 (auth jest UDP, a klient TCP wchodzi w ROOT) -> potem GET z WAW przez UDP"
expect_set_ok TCP "$P0" auth 8123
sleep_step
expect_get_value UDP "$P1_WAW" auth 8123
sleep_step

echo "- SET mail=7777 (mail jest TCP, klient UDP wchodzi w GDN) -> potem GET z ROOT (TCP)"
expect_set_ok UDP "$P1_GDN" mail 7777
sleep_step
expect_get_value TCP "$P0" mail 7777
sleep_step

# ------------------------------------------------------------

title "TEST 5 (150/300/400): NA dla nieistniejacego klucza (proxy moze odpowiedziec sam)"
echo "Co testuje:"
echo "  - Poprawna odpowiedz NA dla klucza spoza sieci"
echo "Komendy:"
echo

echo "- GET VALUE no_such_key z ROOT (TCP)"
expect_na TCP "$P0" GET VALUE no_such_key
sleep_step

echo "- GET VALUE no_such_key z liscia (UDP)"
expect_na UDP "$P3_GDN_A1" GET VALUE no_such_key
sleep_step

# ------------------------------------------------------------

title "TEST 6 (OPCJONALNE / OSTROZNIE): QUIT propagacja (zatrzyma cala siec)"
echo "Co testuje:"
echo "  - Czy QUIT jest przekazywany dalej i czy proxy dba o zamkniecie podleglych serwerow"
echo "UWAGA: to zatrzyma Twoja siec. Odkomentuj tylko gdy chcesz zakonczyc testy i wylaczyc wszystko."
echo

cat <<'EOF'
# Odkomentuj, jesli chcesz:
# java TCPClient -address 127.0.0.1 -port 15100 -command QUIT
# sleep 2
# (opcjonalnie) proba zapytania po QUIT powinna sie nie udac (connection refused / timeout)
EOF

blank
echo "KONIEC: wszystkie testy krytyczne przeszly."
