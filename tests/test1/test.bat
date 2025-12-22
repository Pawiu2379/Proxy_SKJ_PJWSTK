@echo off
setlocal

REM ============================================================
REM FULL_NETWORK_TEST.cmd
REM Wymaganie: cala siec (serwery + proxy) juz dziala.
REM ============================================================

set ADDR=127.0.0.1
set DELAY=2

REM ===== Proxy ports (Twoja topologia) =====
set P0=15000

set P1_WAW=15010
set P2_WAW_A=15011
set P2_WAW_B=15012
set P3_WAW_B1=15013

set P1_KRK=15020
set P2_KRK_A=15021
set P3_KRK_A1=15022

set P1_GDN=15030
set P2_GDN_A=15031
set P3_GDN_A1=15032

echo ============================================================
echo TEST 0: "Sanity check - czy siec zyje (ROOT odpowiada)"
echo Co testuje:
echo   - Czy proxy ROOT odpowiada na GET NAMES
echo   - Czy w ogole da sie rozmawiac z siecia po TCP i UDP
echo Oczekuj:
echo   - OK ... (lista kluczy). Jesli cos nie dziala: timeout/NA/brak odpowiedzi.
echo Komendy:
echo ============================================================
java TCPClient -address %ADDR% -port %P0% -command GET NAMES
timeout /t %DELAY% /nobreak >nul
java UDPClient -address %ADDR% -port %P0% -command GET NAMES
timeout /t %DELAY% /nobreak >nul


echo.
echo ============================================================
echo TEST 1: "Ruch W DOL - odczyt kluczy z lisci (najblizsze serwery)"
echo Co testuje:
echo   - Czy proxy na niskich poziomach potrafia obsluzyc klucze swoich serwerow
echo   - Czy GET VALUE dziala lokalnie bez potrzeby routingu do innych galezi
echo Oczekuj:
echo   - OK <wartosc> dla kluczy przypietych do danego liscia
echo Komendy:
echo ============================================================

echo [P2-waw-a] (ma google + apple)
java TCPClient -address %ADDR% -port %P2_WAW_A% -command GET NAMES
timeout /t %DELAY% /nobreak >nul
java TCPClient -address %ADDR% -port %P2_WAW_A% -command GET VALUE google
timeout /t %DELAY% /nobreak >nul
java UDPClient -address %ADDR% -port %P2_WAW_A% -command GET VALUE apple
timeout /t %DELAY% /nobreak >nul

echo [P3-waw-b1] (ma microsoft + mozilla)
java UDPClient -address %ADDR% -port %P3_WAW_B1% -command GET VALUE microsoft
timeout /t %DELAY% /nobreak >nul
java TCPClient -address %ADDR% -port %P3_WAW_B1% -command GET VALUE mozilla
timeout /t %DELAY% /nobreak >nul

echo [P3-krk-a1] (ma youtube)
java TCPClient -address %ADDR% -port %P3_KRK_A1% -command GET VALUE youtube
timeout /t %DELAY% /nobreak >nul

echo [P3-gdn-a1] (ma twitter + netflix)
java TCPClient -address %ADDR% -port %P3_GDN_A1% -command GET VALUE twitter
timeout /t %DELAY% /nobreak >nul
java UDPClient -address %ADDR% -port %P3_GDN_A1% -command GET VALUE netflix
timeout /t %DELAY% /nobreak >nul


echo.
echo ============================================================
echo TEST 2: "Mostkowanie protokolow - TCP klient do UDP serwera i odwrotnie"
echo Co testuje:
echo   - Czy proxy poprawnie tlumaczy protokoly (TCPClient moze trafic do UDPServer
echo     i UDPClient moze trafic do TCPServer) w OBRĘBIE jednego proxy
echo Oczekuj:
echo   - OK <wartosc> mimo roznicy protokolow klient/serwer
echo Komendy:
echo ============================================================

echo TCPClient -> P2-waw-a -> UDPServer(apple)
java TCPClient -address %ADDR% -port %P2_WAW_A% -command GET VALUE apple
timeout /t %DELAY% /nobreak >nul

echo UDPClient -> P2-waw-a -> TCPServer(google)
java UDPClient -address %ADDR% -port %P2_WAW_A% -command GET VALUE google
timeout /t %DELAY% /nobreak >nul


echo.
echo ============================================================
echo TEST 3: "Ruch W GORE - wejscie nisko, pytanie o klucz z innej galezi"
echo Co testuje:
echo   - Czy zapytanie idzie do rodzica (w gore), bo lokalny proxy nie zna klucza
echo   - Czy rodzic potrafi przekierowac dalej
echo Oczekuj:
echo   - OK <wartosc> dla klucza spoza lokalnego poddrzewa
echo Komendy:
echo ============================================================

echo Wejscie w WAW (P2-waw-a) -> pytanie o KRK (youtube)
java TCPClient -address %ADDR% -port %P2_WAW_A% -command GET VALUE youtube
timeout /t %DELAY% /nobreak >nul

echo Wejscie w KRK (P2-krk-a) -> pytanie o GDN (twitter)
java UDPClient -address %ADDR% -port %P2_KRK_A% -command GET VALUE twitter
timeout /t %DELAY% /nobreak >nul

echo Wejscie w GDN (P2-gdn-a) -> pytanie o WAW (mozilla)
java TCPClient -address %ADDR% -port %P2_GDN_A% -command GET VALUE mozilla
timeout /t %DELAY% /nobreak >nul


echo.
echo ============================================================
echo TEST 4: "Ruch W BOK - wejscie na poziomie miasta (P1), pytania do innych miast"
echo Co testuje:
echo   - Czy na poziomie P1 da sie odpytac klucze z innych P1 (ruch w bok przez ROOT)
echo Oczekuj:
echo   - OK <wartosc> dla kluczy z innych galezi
echo Komendy:
echo ============================================================

echo Wejscie P1-waw -> pytania do KRK i GDN
java TCPClient -address %ADDR% -port %P1_WAW% -command GET VALUE opera
timeout /t %DELAY% /nobreak >nul
java UDPClient -address %ADDR% -port %P1_WAW% -command GET VALUE facebook
timeout /t %DELAY% /nobreak >nul
java TCPClient -address %ADDR% -port %P1_WAW% -command GET VALUE netflix
timeout /t %DELAY% /nobreak >nul

echo Wejscie P1-krk -> pytania do WAW i GDN
java UDPClient -address %ADDR% -port %P1_KRK% -command GET VALUE google
timeout /t %DELAY% /nobreak >nul
java TCPClient -address %ADDR% -port %P1_KRK% -command GET VALUE example
timeout /t %DELAY% /nobreak >nul

echo Wejscie P1-gdn -> pytania do WAW i KRK
java TCPClient -address %ADDR% -port %P1_GDN% -command GET VALUE mozilla
timeout /t %DELAY% /nobreak >nul
java UDPClient -address %ADDR% -port %P1_GDN% -command GET VALUE amazon
timeout /t %DELAY% /nobreak >nul


echo.
echo ============================================================
echo TEST 5: "SET + weryfikacja z innego konca drzewa"
echo Co testuje:
echo   - Czy SET trafia do poprawnego serwera (przez wiele proxy)
echo   - Czy po SET da sie odczytac nowa wartosc z innej galezi (niezalezna sciezka)
echo Oczekuj:
echo   - Po SET: GET VALUE pokazuje nowa wartosc
echo Komendy:
echo ============================================================

echo SET twitter=9009 przez ROOT, odczyt z KRK
java TCPClient -address %ADDR% -port %P0% -command SET twitter 9009
timeout /t %DELAY% /nobreak >nul
java TCPClient -address %ADDR% -port %P1_KRK% -command GET VALUE twitter
timeout /t %DELAY% /nobreak >nul

echo SET amazon=7777 przez WAW, odczyt z GDN
java UDPClient -address %ADDR% -port %P1_WAW% -command SET amazon 7777
timeout /t %DELAY% /nobreak >nul
java UDPClient -address %ADDR% -port %P1_GDN% -command GET VALUE amazon
timeout /t %DELAY% /nobreak >nul

echo SET google=1234 przez GDN, odczyt z WAW (UDP)
java TCPClient -address %ADDR% -port %P1_GDN% -command SET google 1234
timeout /t %DELAY% /nobreak >nul
java UDPClient -address %ADDR% -port %P1_WAW% -command GET VALUE google
timeout /t %DELAY% /nobreak >nul


echo.
echo ============================================================
echo TEST 6: "Nieistniejacy klucz - poprawna odpowiedz NA (bez crasha)"
echo Co testuje:
echo   - Czy proxy zwraca NA dla klucza ktorego nie ma w calej sieci
echo   - Czy siec nie zawiesza sie i nie zapetla routingu
echo Oczekuj:
echo   - NA
echo Komendy:
echo ============================================================
java TCPClient -address %ADDR% -port %P0% -command GET VALUE no_such_key
timeout /t %DELAY% /nobreak >nul
java UDPClient -address %ADDR% -port %P1_WAW% -command GET VALUE no_such_key
timeout /t %DELAY% /nobreak >nul
java TCPClient -address %ADDR% -port %P3_GDN_A1% -command GET VALUE no_such_key
timeout /t %DELAY% /nobreak >nul


echo.
echo ============================================================
echo TEST 7: "Lekka seria zapytan z wielu miejsc (stabilnosc po kilku klientach)"
echo Co testuje:
echo   - Czy po kilku szybkich strzalach z roznych portow/protokolow routing dalej dziala
echo Oczekuj:
echo   - Same OK, bez timeoutow i bez spadkow procesu
echo Komendy:
echo ============================================================
java TCPClient -address %ADDR% -port %P2_KRK_A% -command GET VALUE opera
java UDPClient -address %ADDR% -port %P2_KRK_A% -command GET VALUE youtube
java TCPClient -address %ADDR% -port %P2_GDN_A% -command GET VALUE example
java UDPClient -address %ADDR% -port %P2_GDN_A% -command GET VALUE netflix
java TCPClient -address %ADDR% -port %P2_WAW_B% -command GET VALUE mozilla
timeout /t %DELAY% /nobreak >nul


echo.
echo ============================================================
echo TEST 8: "Dolaczenie nowego serwera w trakcie (update wiedzy proxy)"
echo Co testuje:
echo   - Scenariusz dynamiczny: pojawia sie nowy serwer i nowy klucz (bing)
echo   - Czy (jesli wspierasz hot-join) siec zacznie go widziec bez restartu calej topologii
echo Oczekuj:
echo   - Jesli masz hot-join: GET VALUE bing -> OK 112 oraz GET NAMES moze pokazac wiecej kluczy
echo   - Jesli nie masz hot-join: NA (to nadal ok jako wynik testu, zalezy od Twojej implementacji)
echo Komendy:
echo ============================================================

echo 1) Start nowego serwera S12 (bing=112) w nowym oknie
start "S12-TCP bing:16012" cmd /k java TCPServer -port 16012 -key bing -value 112
timeout /t 2 /nobreak >nul

echo 2) Start nowego proxy P2-waw-c (15014) - laczy S12 i podpina sie do P1-waw
start "P2-waw-c join:15014" cmd /k java Proxy -port 15014 -server %ADDR% 16012 -server %ADDR% %P1_WAW%
timeout /t 4 /nobreak >nul

echo 3) Proba odczytu nowego klucza z ROOTA
java TCPClient -address %ADDR% -port %P0% -command GET VALUE bing
timeout /t %DELAY% /nobreak >nul

echo 4) Proba GET NAMES z ROOTA (czy siec widzi bing)
java TCPClient -address %ADDR% -port %P0% -command GET NAMES
timeout /t %DELAY% /nobreak >nul


echo.
echo ============================================================
echo TEST 9: "Duplikat klucza (odpornosc) - dwa serwery maja ten sam klucz 'google'"
echo Co testuje:
echo   - Sytuacja konfliktowa (czesto w spec jest zakaz duplikatow, ale to test odpornosci)
echo   - Czy siec nie zawiesza sie i nie crashuje, gdy pojawi sie drugi 'google'
echo Oczekuj:
echo   - Zalezne od Twojej polityki: moze zostac stary google, moze nowy, moze NA
echo   - Najwazniejsze: brak petli / brak zwiechy / brak wywalenia procesu
echo Komendy:
echo ============================================================

echo 1) Start dodatkowego serwera S13 (google=9999) w nowym oknie
start "S13-TCP google-dup:16013" cmd /k java TCPServer -port 16013 -key google -value 9999
timeout /t 2 /nobreak >nul

echo 2) Start proxy-dolaczajace P2-dup (15015) - laczy S13 i podpina sie do P1-waw
start "P2-dup join:15015" cmd /k java Proxy -port 15015 -server %ADDR% 16013 -server %ADDR% %P1_WAW%
timeout /t 4 /nobreak >nul

echo 3) Odczyt google z ROOTA (sprawdz jaka wartosc zwraca)
java TCPClient -address %ADDR% -port %P0% -command GET VALUE google
timeout /t %DELAY% /nobreak >nul

echo 4) GET NAMES z ROOTA (czy widzisz objawy duplikatu / jak to liczysz)
java TCPClient -address %ADDR% -port %P0% -command GET NAMES
timeout /t %DELAY% /nobreak >nul


echo.
echo ============================================================
echo KONIEC TESTOW
echo (Opcjonalnie) QUIT wylacza siec - odkomentuj, jesli chcesz.
echo ============================================================
REM java TCPClient -address %ADDR% -port %P0% -command QUIT

pause
endlocal
