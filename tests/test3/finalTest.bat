@echo off
setlocal

echo =========================================================
echo  KOMPILACJA PROJEKTU SKJ (Duza siec - testy w stylu prostym)
echo =========================================================
echo Usuwanie starych plikow .class...
del *.class 2>nul
echo Kompilacja...
javac *.java

if %errorlevel% neq 0 (
    echo BLAD KOMPILACJI! Popraw bledy i sprobuj ponownie.
    pause
    exit /b
)
echo Kompilacja udana.
echo.

REM =========================================================
REM  PORTY (Twoja siec)
REM =========================================================
set ADDR=127.0.0.1

set P0=15500
set P1A=15510
set P1B=15520
set P2A1=15511
set P2A2=15512
set P2B1=15521
set P2B2=15522

set S1=17001
set S2=17002
set S3=17003
set S4=17004
set S5=17005
set S6=17006
set S7=17007
set S8=17008

echo =========================================================
echo  URUCHAMIANIE INFRASTRUKTURY (SERWERY I PROXY)
echo =========================================================

echo [1/3] Start SERWERY (8 szt)...
start "S1 TCP alpha=101 (%S1%)"  cmd /k java TCPServer -port %S1% -key alpha   -value 101
start "S2 UDP beta=102 (%S2%)"   cmd /k java UDPServer -port %S2% -key beta    -value 102
start "S3 UDP gamma=103 (%S3%)"  cmd /k java UDPServer -port %S3% -key gamma   -value 103
start "S4 TCP delta=104 (%S4%)"  cmd /k java TCPServer -port %S4% -key delta   -value 104
start "S5 TCP epsilon=105 (%S5%)" cmd /k java TCPServer -port %S5% -key epsilon -value 105
start "S6 UDP zeta=106 (%S6%)"   cmd /k java UDPServer -port %S6% -key zeta    -value 106
start "S7 TCP eta=107 (%S7%)"    cmd /k java TCPServer -port %S7% -key eta     -value 107
start "S8 UDP theta=108 (%S8%)"  cmd /k java UDPServer -port %S8% -key theta   -value 108

timeout /t 2 >nul

echo [2/3] Start PROXY LISCIE (P2)...
start "P2A1 (%P2A1%) - S1,S2" cmd /k java Proxy -port %P2A1% -server %ADDR% %S1% -server %ADDR% %S2%
start "P2A2 (%P2A2%) - S3,S4" cmd /k java Proxy -port %P2A2% -server %ADDR% %S3% -server %ADDR% %S4%
start "P2B1 (%P2B1%) - S5,S6" cmd /k java Proxy -port %P2B1% -server %ADDR% %S5% -server %ADDR% %S6%
start "P2B2 (%P2B2%) - S7,S8" cmd /k java Proxy -port %P2B2% -server %ADDR% %S7% -server %ADDR% %S8%

timeout /t 2 >nul

echo [3/3] Start PROXY WYZEJ (P1 + ROOT)...
start "P1A (%P1A%) - P2A1,P2A2" cmd /k java Proxy -port %P1A% -server %ADDR% %P2A1% -server %ADDR% %P2A2%
start "P1B (%P1B%) - P2B1,P2B2" cmd /k java Proxy -port %P1B% -server %ADDR% %P2B1% -server %ADDR% %P2B2%
timeout /t 2 >nul
start "P0 ROOT (%P0%) - P1A,P1B" cmd /k java Proxy -port %P0% -server %ADDR% %P1A% -server %ADDR% %P1B%

echo.
echo Czekam 3 sekundy na inicjalizacje polaczen...
timeout /t 3 >nul
echo.

echo =========================================================
echo  ROZPOCZECIE TESTOW
echo =========================================================
echo UWAGA: To sa PROSTE testy: komenda  wynik (bez automatycznej walidacji)
echo.

echo ---------------------------------------------------------
echo TEST 1: GET NAMES (ROOT) - TCP i UDP
echo Co testuje:
echo   - Czy ROOT agreguje liste kluczy z calej sieci
echo Oczekiwany wynik:
echo   - OK 8 alpha beta gamma delta epsilon zeta eta theta (kolejnosc dowolna)
echo Komendy + wynik:
echo ---------------------------------------------------------
echo java TCPClient -address %ADDR% -port %P0% -command GET NAMES
java TCPClient -address %ADDR% -port %P0% -command GET NAMES
echo.
echo java UDPClient -address %ADDR% -port %P0% -command GET NAMES
java UDPClient -address %ADDR% -port %P0% -command GET NAMES
echo.
pause

echo ---------------------------------------------------------
echo TEST 2: Ruch w dol - lokalne klucze na lisciach (P2)
echo Co testuje:
echo   - Czy proxy-lisc obsluguje swoje serwery bez potrzeby routingu dalej
echo Oczekiwany wynik:
echo   - OK 101 / OK 102 / OK 103 / OK 104 itd.
echo Komendy + wynik:
echo ---------------------------------------------------------

echo [P2A1] alpha=101, beta=102
echo java TCPClient -address %ADDR% -port %P2A1% -command GET VALUE alpha
java TCPClient -address %ADDR% -port %P2A1% -command GET VALUE alpha
echo java UDPClient -address %ADDR% -port %P2A1% -command GET VALUE beta
java UDPClient -address %ADDR% -port %P2A1% -command GET VALUE beta
echo.

echo [P2A2] gamma=103, delta=104
echo java UDPClient -address %ADDR% -port %P2A2% -command GET VALUE gamma
java UDPClient -address %ADDR% -port %P2A2% -command GET VALUE gamma
echo java TCPClient -address %ADDR% -port %P2A2% -command GET VALUE delta
java TCPClient -address %ADDR% -port %P2A2% -command GET VALUE delta
echo.

echo [P2B1] epsilon=105, zeta=106
echo java TCPClient -address %ADDR% -port %P2B1% -command GET VALUE epsilon
java TCPClient -address %ADDR% -port %P2B1% -command GET VALUE epsilon
echo java UDPClient -address %ADDR% -port %P2B1% -command GET VALUE zeta
java UDPClient -address %ADDR% -port %P2B1% -command GET VALUE zeta
echo.

echo [P2B2] eta=107, theta=108
echo java TCPClient -address %ADDR% -port %P2B2% -command GET VALUE eta
java TCPClient -address %ADDR% -port %P2B2% -command GET VALUE eta
echo java UDPClient -address %ADDR% -port %P2B2% -command GET VALUE theta
java UDPClient -address %ADDR% -port %P2B2% -command GET VALUE theta
echo.
pause

echo ---------------------------------------------------------
echo TEST 3: Mostkowanie protokolow (TCP  UDP)
echo Co testuje:
echo   - TCPClient potrafi dojsc do UDPServer (np. beta, theta)
echo   - UDPClient potrafi dojsc do TCPServer (np. alpha, eta)
echo Oczekiwany wynik:
echo   - OK 102, OK 101, OK 108, OK 107
echo Komendy + wynik:
echo ---------------------------------------------------------

echo TCPClient - P2A1 - beta (UDP)
echo java TCPClient -address %ADDR% -port %P2A1% -command GET VALUE beta
java TCPClient -address %ADDR% -port %P2A1% -command GET VALUE beta
echo.

echo UDPClient - P2A1 - alpha (TCP)
echo java UDPClient -address %ADDR% -port %P2A1% -command GET VALUE alpha
java UDPClient -address %ADDR% -port %P2A1% -command GET VALUE alpha
echo.

echo TCPClient - P2B2 - theta (UDP)
echo java TCPClient -address %ADDR% -port %P2B2% -command GET VALUE theta
java TCPClient -address %ADDR% -port %P2B2% -command GET VALUE theta
echo.

echo UDPClient - P2B2 - eta (TCP)
echo java UDPClient -address %ADDR% -port %P2B2% -command GET VALUE eta
java UDPClient -address %ADDR% -port %P2B2% -command GET VALUE eta
echo.
pause

echo ---------------------------------------------------------
echo TEST 4: Routing po drzewie (w gore / w bok)
echo Co testuje:
echo   - Wejscie w jedna galez i pytanie o klucz z innej galezi
echo Oczekiwany wynik:
echo   - OK <wartosc> (np. OK 108, OK 105, OK 103)
echo Komendy + wynik:
echo ---------------------------------------------------------

echo Wejscie P2A1 - pytanie o theta (inna galez, P2B2)
echo java TCPClient -address %ADDR% -port %P2A1% -command GET VALUE theta
java TCPClient -address %ADDR% -port %P2A1% -command GET VALUE theta
echo.

echo Wejscie P2B2 - pytanie o alpha (inna galez, P2A1)
echo java UDPClient -address %ADDR% -port %P2B2% -command GET VALUE alpha
java UDPClient -address %ADDR% -port %P2B2% -command GET VALUE alpha
echo.

echo Wejscie P1A - pytanie o epsilon (galez P1B)
echo java TCPClient -address %ADDR% -port %P1A% -command GET VALUE epsilon
java TCPClient -address %ADDR% -port %P1A% -command GET VALUE epsilon
echo.

echo Wejscie ROOT - pytanie o gamma
echo java UDPClient -address %ADDR% -port %P0% -command GET VALUE gamma
java UDPClient -address %ADDR% -port %P0% -command GET VALUE gamma
echo.
pause

echo ---------------------------------------------------------
echo TEST 5: SET + weryfikacja z innej strony drzewa
echo Co testuje:
echo   - Czy SET dociera do serwera i czy widac zmiane z innego proxy
echo Oczekiwany wynik:
echo   - SET: OK
echo   - GET po SET: OK nowa_wartosc
echo Komendy + wynik:
echo ---------------------------------------------------------

echo SET theta=9001 przez ROOT (TCP)
echo java TCPClient -address %ADDR% -port %P0% -command SET theta 9001
java TCPClient -address %ADDR% -port %P0% -command SET theta 9001
echo.

echo Weryfikacja: GET theta z P2A2 (inna galez)
echo java TCPClient -address %ADDR% -port %P2A2% -command GET VALUE theta
java TCPClient -address %ADDR% -port %P2A2% -command GET VALUE theta
echo.
pause

echo ---------------------------------------------------------
echo TEST 6: Nieistniejacy klucz  NA
echo Co testuje:
echo   - Poprawna odpowiedz NA bez zawieszenia
echo Oczekiwany wynik:
echo   - NA
echo Komendy + wynik:
echo ---------------------------------------------------------
echo java TCPClient -address %ADDR% -port %P0% -command GET VALUE no_such_key
java TCPClient -address %ADDR% -port %P0% -command GET VALUE no_such_key
echo.
echo java UDPClient -address %ADDR% -port %P2B1% -command GET VALUE no_such_key
java UDPClient -address %ADDR% -port %P2B1% -command GET VALUE no_such_key
echo.
pause

echo ---------------------------------------------------------
echo TEST 7: QUIT (zamykanie calej sieci)
echo Co testuje:
echo   - QUIT wyslany do ROOTA powinien zamknac proxy i serwery (jesli tak masz w implementacji)
echo   - Obserwuj okna: powinny sie zamknac.
echo Komenda:
echo ---------------------------------------------------------
echo java TCPClient -address %ADDR% -port %P0% -command QUIT
java TCPClient -address %ADDR% -port %P0% -command QUIT

echo.
echo KONIEC. Jesli okna pozamykaly sie po QUIT - test zaliczony.
pause
endlocal
