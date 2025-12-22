@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM SPEC400_ENV_TEST_AND_CLEANUP.bat
REM - javac *.java
REM - stawia środowisko (serwery + proxy) w oknach cmd
REM - testy (pełne komendy w każdym teście)
REM - ENTER => QUIT + taskkill PID
REM ============================================================

set ADDR=127.0.0.1
set DELAY=1

REM ===== PORTY =====
REM Proxy
set P0=15500
set P1A=15510
set P1B=15520
set P2A1=15511
set P2A2=15512
set P2B1=15521
set P2B2=15522

REM Serwery
set S1=17001
set S2=17002
set S3=17003
set S4=17004
set S5=17005
set S6=17006
set S7=17007
set S8=17008

REM Oczekiwane klucze w sieci (posortowane)
set EXPECTED_KEYS_SORTED=alpha beta delta epsilon eta gamma theta zeta

echo ============================================================
echo KOMPILACJA: javac *.java
echo ============================================================
javac *.java
if errorlevel 1 (
  echo FAIL: kompilacja nieudana.
  exit /b 1
)
echo OK: kompilacja zakonczona.
echo.

echo ============================================================
echo ENV: Start serwerow + proxy (okna CMD)
echo ============================================================

REM ============================================================
REM START SERWERY (nowe okna) + PID (PowerShell PassThru)
REM ============================================================

for /f "tokens=1" %%P in ('powershell -NoProfile -Command ^
  "$p=Start-Process cmd -ArgumentList '/k','java TCPServer -port %S1% -key alpha -value 101' -PassThru; $p.Id"') do set PID_S1=%%P
for /f "tokens=1" %%P in ('powershell -NoProfile -Command ^
  "$p=Start-Process cmd -ArgumentList '/k','java UDPServer -port %S2% -key beta -value 102' -PassThru; $p.Id"') do set PID_S2=%%P
for /f "tokens=1" %%P in ('powershell -NoProfile -Command ^
  "$p=Start-Process cmd -ArgumentList '/k','java UDPServer -port %S3% -key gamma -value 103' -PassThru; $p.Id"') do set PID_S3=%%P
for /f "tokens=1" %%P in ('powershell -NoProfile -Command ^
  "$p=Start-Process cmd -ArgumentList '/k','java TCPServer -port %S4% -key delta -value 104' -PassThru; $p.Id"') do set PID_S4=%%P
for /f "tokens=1" %%P in ('powershell -NoProfile -Command ^
  "$p=Start-Process cmd -ArgumentList '/k','java TCPServer -port %S5% -key epsilon -value 105' -PassThru; $p.Id"') do set PID_S5=%%P
for /f "tokens=1" %%P in ('powershell -NoProfile -Command ^
  "$p=Start-Process cmd -ArgumentList '/k','java UDPServer -port %S6% -key zeta -value 106' -PassThru; $p.Id"') do set PID_S6=%%P
for /f "tokens=1" %%P in ('powershell -NoProfile -Command ^
  "$p=Start-Process cmd -ArgumentList '/k','java TCPServer -port %S7% -key eta -value 107' -PassThru; $p.Id"') do set PID_S7=%%P
for /f "tokens=1" %%P in ('powershell -NoProfile -Command ^
  "$p=Start-Process cmd -ArgumentList '/k','java UDPServer -port %S8% -key theta -value 108' -PassThru; $p.Id"') do set PID_S8=%%P

timeout /t 1 /nobreak >nul

REM ============================================================
REM START PROXY (od liści do roota) + PID
REM ============================================================

for /f "tokens=1" %%P in ('powershell -NoProfile -Command ^
  "$p=Start-Process cmd -ArgumentList '/k','java Proxy -port %P2A1% -server %ADDR% %S1% -server %ADDR% %S2%' -PassThru; $p.Id"') do set PID_P2A1=%%P
for /f "tokens=1" %%P in ('powershell -NoProfile -Command ^
  "$p=Start-Process cmd -ArgumentList '/k','java Proxy -port %P2A2% -server %ADDR% %S3% -server %ADDR% %S4%' -PassThru; $p.Id"') do set PID_P2A2=%%P
for /f "tokens=1" %%P in ('powershell -NoProfile -Command ^
  "$p=Start-Process cmd -ArgumentList '/k','java Proxy -port %P2B1% -server %ADDR% %S5% -server %ADDR% %S6%' -PassThru; $p.Id"') do set PID_P2B1=%%P
for /f "tokens=1" %%P in ('powershell -NoProfile -Command ^
  "$p=Start-Process cmd -ArgumentList '/k','java Proxy -port %P2B2% -server %ADDR% %S7% -server %ADDR% %S8%' -PassThru; $p.Id"') do set PID_P2B2=%%P

timeout /t 1 /nobreak >nul

for /f "tokens=1" %%P in ('powershell -NoProfile -Command ^
  "$p=Start-Process cmd -ArgumentList '/k','java Proxy -port %P1A% -server %ADDR% %P2A1% -server %ADDR% %P2A2%' -PassThru; $p.Id"') do set PID_P1A=%%P
for /f "tokens=1" %%P in ('powershell -NoProfile -Command ^
  "$p=Start-Process cmd -ArgumentList '/k','java Proxy -port %P1B% -server %ADDR% %P2B1% -server %ADDR% %P2B2%' -PassThru; $p.Id"') do set PID_P1B=%%P

timeout /t 1 /nobreak >nul

for /f "tokens=1" %%P in ('powershell -NoProfile -Command ^
  "$p=Start-Process cmd -ArgumentList '/k','java Proxy -port %P0% -server %ADDR% %P1A% -server %ADDR% %P1B%' -PassThru; $p.Id"') do set PID_P0=%%P

REM ============================================================
REM Czekanie aż ROOT odpowie na GET NAMES
REM ============================================================

echo.
echo INFO: Czekam az ROOT odpowie na GET NAMES (max 10 prob)...
set ROOT_OK=0
set ROOT_LINE=
for /L %%i in (1,1,10) do (
  for /f "usebackq delims=" %%L in (`java TCPClient -address %ADDR% -port %P0% -command "GET NAMES" 2^>nul ^| findstr /b /c:"OK "`) do (
    set ROOT_OK=1
    set ROOT_LINE=%%L
  )
  if "!ROOT_OK!"=="1" goto ROOT_READY
  timeout /t 1 /nobreak >nul
)
:ROOT_READY
if "%ROOT_OK%"=="0" (
  echo FAIL: ROOT nie odpowiada. Sprawdz okna serwerow/proxy.
  goto CLEANUP
)
echo INFO: ROOT OK: %ROOT_LINE%
echo.

REM ============================================================
REM TEST 0
REM ============================================================
echo ============================================================
echo TEST 0: Sanity – serwery odpowiadaja bezposrednio
echo Co testuje:
echo   - TCP/UDP serwer zwraca "OK <wartosc>" na GET VALUE
echo Komendy:
echo ============================================================

echo java TCPClient -address %ADDR% -port %S1% -command "GET VALUE alpha"
for /f "usebackq delims=" %%L in (`java TCPClient -address %ADDR% -port %S1% -command "GET VALUE alpha"`) do set OUT=%%L
echo   -^> %OUT%
if not "%OUT%"=="OK 101" (echo FAIL expected "OK 101" & goto CLEANUP)
timeout /t %DELAY% /nobreak >nul

echo java UDPClient -address %ADDR% -port %S2% -command "GET VALUE beta"
for /f "usebackq delims=" %%L in (`java UDPClient -address %ADDR% -port %S2% -command "GET VALUE beta"`) do set OUT=%%L
echo   -^> %OUT%
if not "%OUT%"=="OK 102" (echo FAIL expected "OK 102" & goto CLEANUP)
timeout /t %DELAY% /nobreak >nul

echo PASS
echo.

REM ============================================================
REM TEST 1
REM ============================================================
echo ============================================================
echo TEST 1: GET NAMES na ROOT (TCP i UDP) – licznik + pelna lista
echo Co testuje:
echo   - Format: OK ^<liczba^> ^<nazwy...^>
echo   - Liczba=8 oraz 8 unikalnych nazw w calej sieci
echo Komendy:
echo ============================================================

echo java TCPClient -address %ADDR% -port %P0% -command "GET NAMES"
for /f "usebackq delims=" %%L in (`java TCPClient -address %ADDR% -port %P0% -command "GET NAMES"`) do set OUT=%%L
echo   -^> %OUT%
echo %OUT% | findstr /b /c:"OK " >nul || (echo FAIL GET NAMES TCP nie OK & goto CLEANUP)

for /f "tokens=2" %%C in ("%OUT%") do set CNT=%%C
if not "%CNT%"=="8" (echo FAIL licznik TCP != 8, got=%CNT% & goto CLEANUP)

echo %OUT%> "%TEMP%\names_tcp_line.txt"
powershell -NoProfile -Command ^
  "$t=(Get-Content $env:TEMP\names_tcp_line.txt).Split(' '); $names=$t[2..($t.Length-1)] ^| Sort-Object; $s=($names -join ' '); Set-Content $env:TEMP\names_tcp_sorted.txt $s"
set /p SORTED=<"%TEMP%\names_tcp_sorted.txt"
if /I not "%SORTED%"=="%EXPECTED_KEYS_SORTED%" (
  echo FAIL lista nazw TCP nie pasuje
  echo Expected: %EXPECTED_KEYS_SORTED%
  echo Got:      %SORTED%
  goto CLEANUP
)
timeout /t %DELAY% /nobreak >nul

echo java UDPClient -address %ADDR% -port %P0% -command "GET NAMES"
for /f "usebackq delims=" %%L in (`java UDPClient -address %ADDR% -port %P0% -command "GET NAMES"`) do set OUT=%%L
echo   -^> %OUT%
echo %OUT% | findstr /b /c:"OK " >nul || (echo FAIL GET NAMES UDP nie OK & goto CLEANUP)

for /f "tokens=2" %%C in ("%OUT%") do set CNT=%%C
if not "%CNT%"=="8" (echo FAIL licznik UDP != 8, got=%CNT% & goto CLEANUP)

echo %OUT%> "%TEMP%\names_udp_line.txt"
powershell -NoProfile -Command ^
  "$t=(Get-Content $env:TEMP\names_udp_line.txt).Split(' '); $names=$t[2..($t.Length-1)] ^| Sort-Object; $s=($names -join ' '); Set-Content $env:TEMP\names_udp_sorted.txt $s"
set /p SORTED=<"%TEMP%\names_udp_sorted.txt"
if /I not "%SORTED%"=="%EXPECTED_KEYS_SORTED%" (
  echo FAIL lista nazw UDP nie pasuje
  echo Expected: %EXPECTED_KEYS_SORTED%
  echo Got:      %SORTED%
  goto CLEANUP
)

echo PASS
echo.

REM ============================================================
REM TEST 2
REM ============================================================
echo ============================================================
echo TEST 2: Ruch w dol + mostkowanie TCP^<^->UDP na P2-A1
echo Co testuje:
echo   - Lokalnie: alpha(TCP), beta(UDP)
echo   - Mostkowanie: TCPClient->beta(UDP), UDPClient->alpha(TCP)
echo Komendy:
echo ============================================================

echo java TCPClient -address %ADDR% -port %P2A1% -command "GET VALUE alpha"
for /f "usebackq delims=" %%L in (`java TCPClient -address %ADDR% -port %P2A1% -command "GET VALUE alpha"`) do set OUT=%%L
echo   -^> %OUT%
if not "%OUT%"=="OK 101" (echo FAIL expected OK 101 & goto CLEANUP)
timeout /t %DELAY% /nobreak >nul

echo java UDPClient -address %ADDR% -port %P2A1% -command "GET VALUE beta"
for /f "usebackq delims=" %%L in (`java UDPClient -address %ADDR% -port %P2A1% -command "GET VALUE beta"`) do set OUT=%%L
echo   -^> %OUT%
if not "%OUT%"=="OK 102" (echo FAIL expected OK 102 & goto CLEANUP)
timeout /t %DELAY% /nobreak >nul

echo java TCPClient -address %ADDR% -port %P2A1% -command "GET VALUE beta"
for /f "usebackq delims=" %%L in (`java TCPClient -address %ADDR% -port %P2A1% -command "GET VALUE beta"`) do set OUT=%%L
echo   -^> %OUT%
if not "%OUT%"=="OK 102" (echo FAIL expected OK 102 & goto CLEANUP)
timeout /t %DELAY% /nobreak >nul

echo java UDPClient -address %ADDR% -port %P2A1% -command "GET VALUE alpha"
for /f "usebackq delims=" %%L in (`java UDPClient -address %ADDR% -port %P2A1% -command "GET VALUE alpha"`) do set OUT=%%L
echo   -^> %OUT%
if not "%OUT%"=="OK 101" (echo FAIL expected OK 101 & goto CLEANUP)
timeout /t %DELAY% /nobreak >nul

echo PASS
echo.

REM ============================================================
REM TEST 3
REM ============================================================
echo ============================================================
echo TEST 3: Routing proxy^<^->proxy (drzewo) – inne galezie
echo Co testuje:
echo   - Wejscie w A i pytanie o klucz z B
echo   - Wejscie w B i pytanie o klucz z A
echo Komendy:
echo ============================================================

echo java TCPClient -address %ADDR% -port %P2A2% -command "GET VALUE epsilon"
for /f "usebackq delims=" %%L in (`java TCPClient -address %ADDR% -port %P2A2% -command "GET VALUE epsilon"`) do set OUT=%%L
echo   -^> %OUT%
if not "%OUT%"=="OK 105" (echo FAIL expected OK 105 & goto CLEANUP)
timeout /t %DELAY% /nobreak >nul

echo java UDPClient -address %ADDR% -port %P2B2% -command "GET VALUE gamma"
for /f "usebackq delims=" %%L in (`java UDPClient -address %ADDR% -port %P2B2% -command "GET VALUE gamma"`) do set OUT=%%L
echo   -^> %OUT%
if not "%OUT%"=="OK 103" (echo FAIL expected OK 103 & goto CLEANUP)
timeout /t %DELAY% /nobreak >nul

echo PASS
echo.

REM ============================================================
REM TEST 4
REM ============================================================
echo ============================================================
echo TEST 4: SET + weryfikacja z innej galezi
echo Co testuje:
echo   - SET dociera do serwera
echo   - Odczyt innym wejsciem widzi nowa wartosc
echo Komendy:
echo ============================================================

echo java TCPClient -address %ADDR% -port %P0% -command "SET theta 9001"
for /f "usebackq delims=" %%L in (`java TCPClient -address %ADDR% -port %P0% -command "SET theta 9001"`) do set OUT=%%L
echo   -^> %OUT%
if not "%OUT%"=="OK" (echo FAIL expected OK & goto CLEANUP)
timeout /t %DELAY% /nobreak >nul

echo java UDPClient -address %ADDR% -port %P2A1% -command "GET VALUE theta"
for /f "usebackq delims=" %%L in (`java UDPClient -address %ADDR% -port %P2A1% -command "GET VALUE theta"`) do set OUT=%%L
echo   -^> %OUT%
if not "%OUT%"=="OK 9001" (echo FAIL expected OK 9001 & goto CLEANUP)
timeout /t %DELAY% /nobreak >nul

echo java UDPClient -address %ADDR% -port %P1B% -command "SET beta 8123"
for /f "usebackq delims=" %%L in (`java UDPClient -address %ADDR% -port %P1B% -command "SET beta 8123"`) do set OUT=%%L
echo   -^> %OUT%
if not "%OUT%"=="OK" (echo FAIL expected OK & goto CLEANUP)
timeout /t %DELAY% /nobreak >nul

echo java TCPClient -address %ADDR% -port %P2A2% -command "GET VALUE beta"
for /f "usebackq delims=" %%L in (`java TCPClient -address %ADDR% -port %P2A2% -command "GET VALUE beta"`) do set OUT=%%L
echo   -^> %OUT%
if not "%OUT%"=="OK 8123" (echo FAIL expected OK 8123 & goto CLEANUP)
timeout /t %DELAY% /nobreak >nul

echo PASS
echo.

REM ============================================================
REM TEST 5
REM ============================================================
echo ============================================================
echo TEST 5: Nieistniejacy klucz – NA
echo Co testuje:
echo   - Klucz spoza sieci => NA (bez zawiech)
echo Komendy:
echo ============================================================

echo java TCPClient -address %ADDR% -port %P0% -command "GET VALUE no_such_key"
for /f "usebackq delims=" %%L in (`java TCPClient -address %ADDR% -port %P0% -command "GET VALUE no_such_key"`) do set OUT=%%L
echo   -^> %OUT%
if not "%OUT%"=="NA" (echo FAIL expected NA & goto CLEANUP)
timeout /t %DELAY% /nobreak >nul

echo java UDPClient -address %ADDR% -port %P2B1% -command "GET VALUE no_such_key"
for /f "usebackq delims=" %%L in (`java UDPClient -address %ADDR% -port %P2B1% -command "GET VALUE no_such_key"`) do set OUT=%%L
echo   -^> %OUT%
if not "%OUT%"=="NA" (echo FAIL expected NA & goto CLEANUP)
timeout /t %DELAY% /nobreak >nul

echo PASS
echo.

echo ============================================================
echo WYNIK: Wszystkie testy przeszly.
echo Nacisnij ENTER aby zamknac wszystkie okna (cleanup).
echo ============================================================
pause >nul

:CLEANUP
echo.
echo ============================================================
echo CLEANUP: QUIT + taskkill PID
echo ============================================================

REM protokołowo (jeśli QUIT obsługiwane)
java TCPClient -address %ADDR% -port %P0% -command QUIT >nul 2>&1

timeout /t 1 /nobreak >nul

REM Zamknij proxy
for %%X in (%PID_P0% %PID_P1A% %PID_P1B% %PID_P2A1% %PID_P2A2% %PID_P2B1% %PID_P2B2%) do (
  if not "%%X"=="" taskkill /PID %%X /T /F >nul 2>&1
)

REM Zamknij serwery
for %%X in (%PID_S1% %PID_S2% %PID_S3% %PID_S4% %PID_S5% %PID_S6% %PID_S7% %PID_S8%) do (
  if not "%%X"=="" taskkill /PID %%X /T /F >nul 2>&1
)

echo OK: srodowisko zamkniete.
endlocal
exit /b 0
