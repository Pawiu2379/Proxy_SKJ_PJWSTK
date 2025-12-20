#!/usr/bin/env bash
set -euo pipefail

ADDR="127.0.0.1"
DELAY=1
TMO="3s"

# timeout (jeśli dostępny)
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT="timeout $TMO"
else
  TIMEOUT=""
fi

# ===== PORTY =====
# Proxy
P0=15500
P1A=15510
P1B=15520
P2A1=15511
P2A2=15512
P2B1=15521
P2B2=15522

# Serwery
S1=17001
S2=17002
S3=17003
S4=17004
S5=17005
S6=17006
S7=17007
S8=17008

# Oczekiwane klucze w sieci
EXPECTED_SORTED="$(printf "%s\n" alpha beta gamma delta epsilon zeta eta theta | sort | tr '\n' ' ' | sed 's/ $//')"

LOG_DIR="./logs_spec400_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

echo "============================================================"
echo "ENV: Stawiam środowisko testowe (serwery + proxy)"
echo "Logi: $LOG_DIR"
echo "============================================================"

# ===== SERWERY (w tle) =====
java TCPServer -port "$S1" -key alpha   -value 101 >"$LOG_DIR/S1_TCP_alpha.log" 2>&1 & PID_S1=$!
java UDPServer -port "$S2" -key beta    -value 102 >"$LOG_DIR/S2_UDP_beta.log"  2>&1 & PID_S2=$!
java UDPServer -port "$S3" -key gamma   -value 103 >"$LOG_DIR/S3_UDP_gamma.log" 2>&1 & PID_S3=$!
java TCPServer -port "$S4" -key delta   -value 104 >"$LOG_DIR/S4_TCP_delta.log" 2>&1 & PID_S4=$!
java TCPServer -port "$S5" -key epsilon -value 105 >"$LOG_DIR/S5_TCP_epsilon.log" 2>&1 & PID_S5=$!
java UDPServer -port "$S6" -key zeta    -value 106 >"$LOG_DIR/S6_UDP_zeta.log"  2>&1 & PID_S6=$!
java TCPServer -port "$S7" -key eta     -value 107 >"$LOG_DIR/S7_TCP_eta.log"   2>&1 & PID_S7=$!
java UDPServer -port "$S8" -key theta   -value 108 >"$LOG_DIR/S8_UDP_theta.log" 2>&1 & PID_S8=$!

sleep 1

# ===== PROXY (od liści do roota) =====
java Proxy -port "$P2A1" -server "$ADDR" "$S1" -server "$ADDR" "$S2" >"$LOG_DIR/P2A1_15511.log" 2>&1 & PID_P2A1=$!
java Proxy -port "$P2A2" -server "$ADDR" "$S3" -server "$ADDR" "$S4" >"$LOG_DIR/P2A2_15512.log" 2>&1 & PID_P2A2=$!
java Proxy -port "$P2B1" -server "$ADDR" "$S5" -server "$ADDR" "$S6" >"$LOG_DIR/P2B1_15521.log" 2>&1 & PID_P2B1=$!
java Proxy -port "$P2B2" -server "$ADDR" "$S7" -server "$ADDR" "$S8" >"$LOG_DIR/P2B2_15522.log" 2>&1 & PID_P2B2=$!

sleep 1

java Proxy -port "$P1A" -server "$ADDR" "$P2A1" -server "$ADDR" "$P2A2" >"$LOG_DIR/P1A_15510.log" 2>&1 & PID_P1A=$!
java Proxy -port "$P1B" -server "$ADDR" "$P2B1" -server "$ADDR" "$P2B2" >"$LOG_DIR/P1B_15520.log" 2>&1 & PID_P1B=$!

sleep 1

java Proxy -port "$P0" -server "$ADDR" "$P1A" -server "$ADDR" "$P1B" >"$LOG_DIR/P0_15500.log" 2>&1 & PID_P0=$!

# Czekamy aż ROOT odpowie na GET NAMES
echo "INFO: Czekam aż ROOT zacznie odpowiadać na GET NAMES..."
ROOT_OK=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  OUT="$($TIMEOUT java TCPClient -address "$ADDR" -port "$P0" -command GET\ NAMES 2>/dev/null | awk 'NF{l=$0} END{print l}' || true)"
  if [[ "$OUT" == OK\ * ]]; then
    echo "INFO: ROOT odpowiada (próba $i): $OUT"
    ROOT_OK=1
    break
  fi
  sleep 1
done

if [[ "$ROOT_OK" != "1" ]]; then
  echo "FAIL: ROOT nie odpowiada. Sprawdź logi: $LOG_DIR"
  exit 1
fi

sleep 1
echo

# ============================================================
# TESTY (pełne komendy wprost)
# ============================================================

echo "============================================================"
echo "TEST 0: Sanity – serwery odpowiadają bezpośrednio"
echo "Co testuje:"
echo "  - Czy serwer TCP i UDP odpowiadają OK <wartość> na GET VALUE"
echo "Komendy:"
echo "  java TCPClient -address $ADDR -port $S1 -command GET VALUE alpha"
OUT="$($TIMEOUT java TCPClient -address "$ADDR" -port "$S1" -command GET\ VALUE\ alpha 2>&1 | awk 'NF{l=$0} END{print l}')"
echo "  -> $OUT"
if [[ "$OUT" != "OK 101" ]]; then echo "FAIL: expected 'OK 101'"; exit 1; fi
sleep "$DELAY"

echo "  java UDPClient -address $ADDR -port $S2 -command GET VALUE beta"
OUT="$($TIMEOUT java UDPClient -address "$ADDR" -port "$S2" -command GET\ VALUE\ beta 2>&1 | awk 'NF{l=$0} END{print l}')"
echo "  -> $OUT"
if [[ "$OUT" != "OK 102" ]]; then echo "FAIL: expected 'OK 102'"; exit 1; fi
sleep "$DELAY"
echo "PASS"
echo

echo "============================================================"
echo "TEST 1: GET NAMES na ROOT (TCP i UDP) – licznik + pełna lista"
echo "Co testuje:"
echo "  - Format odpowiedzi: OK <liczba> <nazwy...>"
echo "  - Liczba=8 i dokładnie 8 unikalnych kluczy w sieci"
echo "Komendy:"
echo "  java TCPClient -address $ADDR -port $P0 -command GET NAMES"
OUT="$($TIMEOUT java TCPClient -address "$ADDR" -port "$P0" -command GET\ NAMES 2>&1 | awk 'NF{l=$0} END{print l}')"
echo "  -> $OUT"
if [[ "$OUT" != OK\ * ]]; then echo "FAIL: GET NAMES (TCP) nie zwrócił OK"; exit 1; fi
COUNT="$(echo "$OUT" | awk '{print $2}')"
if [[ "$COUNT" != "8" ]]; then echo "FAIL: licznik != 8 (TCP), got=$COUNT"; exit 1; fi
SORTED="$(echo "$OUT" | cut -d' ' -f3- | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
if [[ "$SORTED" != "$EXPECTED_SORTED" ]]; then
  echo "FAIL: lista nazw (TCP) nie pasuje"
  echo "Expected: $EXPECTED_SORTED"
  echo "Got:      $SORTED"
  exit 1
fi
sleep "$DELAY"

echo "  java UDPClient -address $ADDR -port $P0 -command GET NAMES"
OUT="$($TIMEOUT java UDPClient -address "$ADDR" -port "$P0" -command GET\ NAMES 2>&1 | awk 'NF{l=$0} END{print l}')"
echo "  -> $OUT"
if [[ "$OUT" != OK\ * ]]; then echo "FAIL: GET NAMES (UDP) nie zwrócił OK"; exit 1; fi
COUNT="$(echo "$OUT" | awk '{print $2}')"
if [[ "$COUNT" != "8" ]]; then echo "FAIL: licznik != 8 (UDP), got=$COUNT"; exit 1; fi
SORTED="$(echo "$OUT" | cut -d' ' -f3- | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
if [[ "$SORTED" != "$EXPECTED_SORTED" ]]; then
  echo "FAIL: lista nazw (UDP) nie pasuje"
  echo "Expected: $EXPECTED_SORTED"
  echo "Got:      $SORTED"
  exit 1
fi
sleep "$DELAY"
echo "PASS"
echo

echo "============================================================"
echo "TEST 2: Ruch w dół + mostkowanie TCP<->UDP na liściu P2-A1"
echo "Co testuje:"
echo "  - Lokalny dostęp do alpha(TCP) i beta(UDP)"
echo "  - TCPClient może pobrać beta (UDP server) i UDPClient może pobrać alpha (TCP server)"
echo "Komendy:"

echo "  java TCPClient -address $ADDR -port $P2A1 -command GET VALUE alpha"
OUT="$($TIMEOUT java TCPClient -address "$ADDR" -port "$P2A1" -command GET\ VALUE\ alpha 2>&1 | awk 'NF{l=$0} END{print l}')"
echo "  -> $OUT"
if [[ "$OUT" != "OK 101" ]]; then echo "FAIL: expected 'OK 101'"; exit 1; fi
sleep "$DELAY"

echo "  java UDPClient -address $ADDR -port $P2A1 -command GET VALUE beta"
OUT="$($TIMEOUT java UDPClient -address "$ADDR" -port "$P2A1" -command GET\ VALUE\ beta 2>&1 | awk 'NF{l=$0} END{print l}')"
echo "  -> $OUT"
if [[ "$OUT" != "OK 102" ]]; then echo "FAIL: expected 'OK 102'"; exit 1; fi
sleep "$DELAY"

echo "  java TCPClient -address $ADDR -port $P2A1 -command GET VALUE beta"
OUT="$($TIMEOUT java TCPClient -address "$ADDR" -port "$P2A1" -command GET\ VALUE\ beta 2>&1 | awk 'NF{l=$0} END{print l}')"
echo "  -> $OUT"
if [[ "$OUT" != "OK 102" ]]; then echo "FAIL: expected 'OK 102'"; exit 1; fi
sleep "$DELAY"

echo "  java UDPClient -address $ADDR -port $P2A1 -command GET VALUE alpha"
OUT="$($TIMEOUT java UDPClient -address "$ADDR" -port "$P2A1" -command GET\ VALUE\ alpha 2>&1 | awk 'NF{l=$0} END{print l}')"
echo "  -> $OUT"
if [[ "$OUT" != "OK 101" ]]; then echo "FAIL: expected 'OK 101'"; exit 1; fi
sleep "$DELAY"

echo "PASS"
echo

echo "============================================================"
echo "TEST 3: Routing proxy->proxy (drzewo) – pytania o klucze z innej gałęzi"
echo "Co testuje:"
echo "  - Wejście w gałąź A i pytanie o klucz z gałęzi B"
echo "  - Wejście w gałąź B i pytanie o klucz z gałęzi A"
echo "Komendy:"

echo "  java TCPClient -address $ADDR -port $P2A2 -command GET VALUE epsilon"
OUT="$($TIMEOUT java TCPClient -address "$ADDR" -port "$P2A2" -command GET\ VALUE\ epsilon 2>&1 | awk 'NF{l=$0} END{print l}')"
echo "  -> $OUT"
if [[ "$OUT" != "OK 105" ]]; then echo "FAIL: expected 'OK 105'"; exit 1; fi
sleep "$DELAY"

echo "  java UDPClient -address $ADDR -port $P2B2 -command GET VALUE gamma"
OUT="$($TIMEOUT java UDPClient -address "$ADDR" -port "$P2B2" -command GET\ VALUE\ gamma 2>&1 | awk 'NF{l=$0} END{print l}')"
echo "  -> $OUT"
if [[ "$OUT" != "OK 103" ]]; then echo "FAIL: expected 'OK 103'"; exit 1; fi
sleep "$DELAY"

echo "PASS"
echo

echo "============================================================"
echo "TEST 4: SET + weryfikacja z innego miejsca w drzewie"
echo "Co testuje:"
echo "  - SET dociera do właściwego serwera"
echo "  - Odczyt inną ścieżką widzi zmianę"
echo "Komendy:"

echo "  java TCPClient -address $ADDR -port $P0 -command SET theta 9001"
OUT="$($TIMEOUT java TCPClient -address "$ADDR" -port "$P0" -command SET\ theta\ 9001 2>&1 | awk 'NF{l=$0} END{print l}')"
echo "  -> $OUT"
if [[ "$OUT" != "OK" ]]; then echo "FAIL: expected 'OK'"; exit 1; fi
sleep "$DELAY"

echo "  java UDPClient -address $ADDR -port $P2A1 -command GET VALUE theta"
OUT="$($TIMEOUT java UDPClient -address "$ADDR" -port "$P2A1" -command GET\ VALUE\ theta 2>&1 | awk 'NF{l=$0} END{print l}')"
echo "  -> $OUT"
if [[ "$OUT" != "OK 9001" ]]; then echo "FAIL: expected 'OK 9001'"; exit 1; fi
sleep "$DELAY"

echo "  java UDPClient -address $ADDR -port $P1B -command SET beta 8123"
OUT="$($TIMEOUT java UDPClient -address "$ADDR" -port "$P1B" -command SET\ beta\ 8123 2>&1 | awk 'NF{l=$0} END{print l}')"
echo "  -> $OUT"
if [[ "$OUT" != "OK" ]]; then echo "FAIL: expected 'OK'"; exit 1; fi
sleep "$DELAY"

echo "  java TCPClient -address $ADDR -port $P2A2 -command GET VALUE beta"
OUT="$($TIMEOUT java TCPClient -address "$ADDR" -port "$P2A2" -command GET\ VALUE\ beta 2>&1 | awk 'NF{l=$0} END{print l}')"
echo "  -> $OUT"
if [[ "$OUT" != "OK 8123" ]]; then echo "FAIL: expected 'OK 8123'"; exit 1; fi
sleep "$DELAY"

echo "PASS"
echo

echo "============================================================"
echo "TEST 5: Nieistniejący klucz – NA"
echo "Co testuje:"
echo "  - Jeśli klucza nie ma w sieci, odpowiedź musi być NA (bez zawiechy)"
echo "Komendy:"

echo "  java TCPClient -address $ADDR -port $P0 -command GET VALUE no_such_key"
OUT="$($TIMEOUT java TCPClient -address "$ADDR" -port "$P0" -command GET\ VALUE\ no_such_key 2>&1 | awk 'NF{l=$0} END{print l}')"
echo "  -> $OUT"
if [[ "$OUT" != "NA" ]]; then echo "FAIL: expected 'NA'"; exit 1; fi
sleep "$DELAY"

echo "  java UDPClient -address $ADDR -port $P2B1 -command GET VALUE no_such_key"
OUT="$($TIMEOUT java UDPClient -address "$ADDR" -port "$P2B1" -command GET\ VALUE\ no_such_key 2>&1 | awk 'NF{l=$0} END{print l}')"
echo "  -> $OUT"
if [[ "$OUT" != "NA" ]]; then echo "FAIL: expected 'NA'"; exit 1; fi
sleep "$DELAY"

echo "PASS"
echo

echo "============================================================"
echo "WYNIK: Wszystkie testy przeszły."
echo "Naciśnij ENTER aby usunąć środowisko testowe (kill procesów)."
echo "============================================================"
read -r _

echo "INFO: Sprzątanie... (najpierw QUIT do roota, potem kill PID-ów)"
$TIMEOUT java TCPClient -address "$ADDR" -port "$P0" -command QUIT >/dev/null 2>&1 || true
sleep 1

# Kill (proxy)
kill "$PID_P0"  >/dev/null 2>&1 || true
kill "$PID_P1A" >/dev/null 2>&1 || true
kill "$PID_P1B" >/dev/null 2>&1 || true
kill "$PID_P2A1" >/dev/null 2>&1 || true
kill "$PID_P2A2" >/dev/null 2>&1 || true
kill "$PID_P2B1" >/dev/null 2>&1 || true
kill "$PID_P2B2" >/dev/null 2>&1 || true

# Kill (servers)
kill "$PID_S1" >/dev/null 2>&1 || true
kill "$PID_S2" >/dev/null 2>&1 || true
kill "$PID_S3" >/dev/null 2>&1 || true
kill "$PID_S4" >/dev/null 2>&1 || true
kill "$PID_S5" >/dev/null 2>&1 || true
kill "$PID_S6" >/dev/null 2>&1 || true
kill "$PID_S7" >/dev/null 2>&1 || true
kill "$PID_S8" >/dev/null 2>&1 || true

sleep 1

# Dobić jeśli coś zostało
kill -9 "$PID_P0" "$PID_P1A" "$PID_P1B" "$PID_P2A1" "$PID_P2A2" "$PID_P2B1" "$PID_P2B2" >/dev/null 2>&1 || true
kill -9 "$PID_S1" "$PID_S2" "$PID_S3" "$PID_S4" "$PID_S5" "$PID_S6" "$PID_S7" "$PID_S8" >/dev/null 2>&1 || true

echo "OK: środowisko usunięte. Logi zostały w: $LOG_DIR"
