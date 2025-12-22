#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# FULL_NETWORK_TEST (GNOME)
# Wymaganie: cala siec (S1..S11 + proxy P0..P3) juz dziala.
# ============================================================

ADDR="127.0.0.1"
DELAY=2

# ----- helper: new GNOME terminal window -----
run_gnome() {
  local title="$1"
  shift
  local cmd="$*"
  gnome-terminal --title="$title" -- bash -lc "$cmd; exec bash" >/dev/null 2>&1 &
}

# ===== Proxy ports (Twoja topologia) =====
P0=15000

P1_WAW=15010
P2_WAW_A=15011
P2_WAW_B=15012
P3_WAW_B1=15013

P1_KRK=15020
P2_KRK_A=15021
P3_KRK_A1=15022

P1_GDN=15030
P2_GDN_A=15031
P3_GDN_A1=15032


echo "============================================================"
echo 'TEST 0: Sanity check (ROOT odpowiada)'
echo "Co testuje:"
echo "  - Czy ROOT odpowiada na GET NAMES"
echo "  - Czy da sie rozmawiac z siecia po TCP i UDP"
echo "Komendy:"
echo "============================================================"
java TCPClient -address "$ADDR" -port "$P0" -command "GET NAMES"
sleep "$DELAY"
java UDPClient -address "$ADDR" -port "$P0" -command "GET NAMES"
sleep "$DELAY"


echo
echo "============================================================"
echo 'TEST 1: Ruch W DOL (lokalne klucze na lisciach)'
echo "Co testuje:"
echo "  - Czy proxy na niskich poziomach obsluguje klucze swoich serwerow"
echo "Komendy:"
echo "============================================================"

echo "[P2-waw-a] google + apple"
java TCPClient -address "$ADDR" -port "$P2_WAW_A" -command "GET NAMES"
sleep "$DELAY"
java TCPClient -address "$ADDR" -port "$P2_WAW_A" -command "GET VALUE google"
sleep "$DELAY"
java UDPClient -address "$ADDR" -port "$P2_WAW_A" -command "GET VALUE apple"
sleep "$DELAY"

echo "[P3-waw-b1] microsoft + mozilla"
java UDPClient -address "$ADDR" -port "$P3_WAW_B1" -command "GET VALUE microsoft"
sleep "$DELAY"
java TCPClient -address "$ADDR" -port "$P3_WAW_B1" -command "GET VALUE mozilla"
sleep "$DELAY"

echo "[P3-krk-a1] youtube"
java TCPClient -address "$ADDR" -port "$P3_KRK_A1" -command "GET VALUE youtube"
sleep "$DELAY"

echo "[P3-gdn-a1] twitter + netflix"
java TCPClient -address "$ADDR" -port "$P3_GDN_A1" -command "GET VALUE twitter"
sleep "$DELAY"
java UDPClient -address "$ADDR" -port "$P3_GDN_A1" -command "GET VALUE netflix"
sleep "$DELAY"


echo
echo "============================================================"
echo 'TEST 2: Mostkowanie protokolow (TCP klient -> UDP serwer i odwrotnie)'
echo "Co testuje:"
echo "  - Translacje protokolu w proxy (TCPClient<->UDPServer, UDPClient<->TCPServer)"
echo "Komendy:"
echo "============================================================"

echo "TCPClient -> (P2-waw-a) -> UDPServer(apple)"
java TCPClient -address "$ADDR" -port "$P2_WAW_A" -command "GET VALUE apple"
sleep "$DELAY"

echo "UDPClient -> (P2-waw-a) -> TCPServer(google)"
java UDPClient -address "$ADDR" -port "$P2_WAW_A" -command "GET VALUE google"
sleep "$DELAY"


echo
echo "============================================================"
echo 'TEST 3: Ruch W GORE (wejscie nisko -> klucz z innej galezi)'
echo "Co testuje:"
echo "  - Czy zapytanie idzie do rodzica, gdy lokalny proxy nie zna klucza"
echo "Komendy:"
echo "============================================================"

echo "WAW (P2-waw-a) -> pytanie o KRK (youtube)"
java TCPClient -address "$ADDR" -port "$P2_WAW_A" -command "GET VALUE youtube"
sleep "$DELAY"

echo "KRK (P2-krk-a) -> pytanie o GDN (twitter)"
java UDPClient -address "$ADDR" -port "$P2_KRK_A" -command "GET VALUE twitter"
sleep "$DELAY"

echo "GDN (P2-gdn-a) -> pytanie o WAW (mozilla)"
java TCPClient -address "$ADDR" -port "$P2_GDN_A" -command "GET VALUE mozilla"
sleep "$DELAY"


echo
echo "============================================================"
echo 'TEST 4: Ruch W BOK (wejscie na P1 -> klucze z innych miast)'
echo "Co testuje:"
echo "  - Czy na poziomie P1 da sie odpytac klucze z innych galezi (przez ROOT)"
echo "Komendy:"
echo "============================================================"

echo "P1-waw -> opera, facebook, netflix"
java TCPClient -address "$ADDR" -port "$P1_WAW" -command "GET VALUE opera"
sleep "$DELAY"
java UDPClient -address "$ADDR" -port "$P1_WAW" -command "GET VALUE facebook"
sleep "$DELAY"
java TCPClient -address "$ADDR" -port "$P1_WAW" -command "GET VALUE netflix"
sleep "$DELAY"

echo "P1-krk -> google, example"
java UDPClient -address "$ADDR" -port "$P1_KRK" -command "GET VALUE google"
sleep "$DELAY"
java TCPClient -address "$ADDR" -port "$P1_KRK" -command "GET VALUE example"
sleep "$DELAY"

echo "P1-gdn -> mozilla, amazon"
java TCPClient -address "$ADDR" -port "$P1_GDN" -command "GET VALUE mozilla"
sleep "$DELAY"
java UDPClient -address "$ADDR" -port "$P1_GDN" -command "GET VALUE amazon"
sleep "$DELAY"


echo
echo "============================================================"
echo 'TEST 5: SET + weryfikacja z innego konca drzewa'
echo "Co testuje:"
echo "  - Czy SET trafia do poprawnego serwera"
echo "  - Czy odczyt z innej galezi widzi nowa wartosc"
echo "Komendy:"
echo "============================================================"

echo "SET twitter=9009 przez ROOT, GET z KRK"
java TCPClient -address "$ADDR" -port "$P0" -command "SET twitter 9009"
sleep "$DELAY"
java TCPClient -address "$ADDR" -port "$P1_KRK" -command "GET VALUE twitter"
sleep "$DELAY"

echo "SET amazon=7777 przez WAW, GET z GDN"
java UDPClient -address "$ADDR" -port "$P1_WAW" -command "SET amazon 7777"
sleep "$DELAY"
java UDPClient -address "$ADDR" -port "$P1_GDN" -command "GET VALUE amazon"
sleep "$DELAY"

echo "SET google=1234 przez GDN, GET z WAW (UDP)"
java TCPClient -address "$ADDR" -port "$P1_GDN" -command "SET google 1234"
sleep "$DELAY"
java UDPClient -address "$ADDR" -port "$P1_WAW" -command "GET VALUE google"
sleep "$DELAY"


echo
echo "============================================================"
echo 'TEST 6: Brakujacy klucz -> NA (bez crasha i bez zwiechy)'
echo "Co testuje:"
echo "  - Poprawna odpowiedz NA i stabilnosc routingu"
echo "Komendy:"
echo "============================================================"
java TCPClient -address "$ADDR" -port "$P0" -command "GET VALUE no_such_key"
sleep "$DELAY"
java UDPClient -address "$ADDR" -port "$P1_WAW" -command "GET VALUE no_such_key"
sleep "$DELAY"
java TCPClient -address "$ADDR" -port "$P3_GDN_A1" -command "GET VALUE no_such_key"
sleep "$DELAY"


echo
echo "============================================================"
echo 'TEST 7: Lekka seria zapytan (stabilnosc po kilku klientach)'
echo "Co testuje:"
echo "  - Czy po kilku szybkich zapytaniach routing dalej dziala"
echo "Komendy:"
echo "============================================================"
java TCPClient -address "$ADDR" -port "$P2_KRK_A" -command "GET VALUE opera"
java UDPClient -address "$ADDR" -port "$P2_KRK_A" -command "GET VALUE youtube"
java TCPClient -address "$ADDR" -port "$P2_GDN_A" -command "GET VALUE example"
java UDPClient -address "$ADDR" -port "$P2_GDN_A" -command "GET VALUE netflix"
java TCPClient -address "$ADDR" -port "$P2_WAW_B" -command "GET VALUE mozilla"
sleep "$DELAY"


echo
echo "============================================================"
echo 'TEST 8: Hot-join (update wiedzy) -> nowy serwer + nowe proxy w trakcie'
echo "Co testuje:"
echo "  - Czy po dolaczeniu nowego serwera (bing) siec zaczyna go widziec (jesli wspierasz hot-join)"
echo "Komendy:"
echo "============================================================"

echo "1) Start S12 (bing=112) w NOWYM OKNIE"
run_gnome "S12-TCP bing:16012" "java TCPServer -port 16012 -key bing -value 112"
sleep 2

echo "2) Start nowego proxy P2-waw-c (15014) podpietego do P1-waw w NOWYM OKNIE"
run_gnome "P2-waw-c join:15014" "java Proxy -port 15014 -server $ADDR 16012 -server $ADDR $P1_WAW"
sleep 4

echo "3) GET VALUE bing z ROOTA"
java TCPClient -address "$ADDR" -port "$P0" -command "GET VALUE bing"
sleep "$DELAY"

echo "4) GET NAMES z ROOTA (czy widac bing)"
java TCPClient -address "$ADDR" -port "$P0" -command "GET NAMES"
sleep "$DELAY"


echo
echo "============================================================"
echo "TEST 9: Duplikat klucza (odpornosc) -> drugi serwer z kluczem 'google'"
echo "Co testuje:"
echo "  - Jak siec zachowuje przy konflikcie nazw (poza zalozeniami spec) i czy nie wiesza sie"
echo "Komendy:"
echo "============================================================"

echo "1) Start S13 (google=9999) w NOWYM OKNIE"
run_gnome "S13-TCP google-dup:16013" "java TCPServer -port 16013 -key google -value 9999"
sleep 2

echo "2) Start proxy P2-dup (15015) podpiete do P1-waw w NOWYM OKNIE"
run_gnome "P2-dup join:15015" "java Proxy -port 15015 -server $ADDR 16013 -server $ADDR $P1_WAW"
sleep 4

echo "3) GET VALUE google z ROOTA"
java TCPClient -address "$ADDR" -port "$P0" -command "GET VALUE google"
sleep "$DELAY"

echo "4) GET NAMES z ROOTA (czy widzisz objawy duplikatu / jak to liczysz)"
java TCPClient -address "$ADDR" -port "$P0" -command "GET NAMES"
sleep "$DELAY"


echo
echo "============================================================"
echo "KONIEC TESTOW"
echo "(Opcjonalnie) QUIT - odkomentuj, jesli chcesz wylaczyc siec."
echo "============================================================"
# java TCPClient -address "$ADDR" -port "$P0" -command "QUIT"

read -r -p "Nacisnij ENTER, aby zakonczyc..." _
