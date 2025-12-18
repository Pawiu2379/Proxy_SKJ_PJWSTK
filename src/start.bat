@echo off

REM WAW
start "S1-TCP google:16001" cmd /k java TCPServer -port 16001 -key google -value 101
start "S2-UDP apple:16002"  cmd /k java UDPServer -port 16002 -key apple  -value 102

REM WAW-B1
start "S3-UDP microsoft:16003" cmd /k java UDPServer -port 16003 -key microsoft -value 103
start "S4-TCP mozilla:16004"   cmd /k java TCPServer -port 16004 -key mozilla   -value 104

REM KRK-A
start "S5-TCP opera:16005"   cmd /k java TCPServer -port 16005 -key opera   -value 105
start "S6-UDP amazon:16006"  cmd /k java UDPServer -port 16006 -key amazon  -value 106
start "S7-TCP youtube:16007" cmd /k java TCPServer -port 16007 -key youtube -value 107

REM GDN
start "S8-UDP facebook:16008" cmd /k java UDPServer -port 16008 -key facebook -value 108
start "S9-TCP twitter:16009"  cmd /k java TCPServer -port 16009 -key twitter  -value 109
start "S10-UDP netflix:16010" cmd /k java UDPServer -port 16010 -key netflix  -value 110
start "S11-TCP example:16011" cmd /k java TCPServer -port 16011 -key example  -value 111


REM ====== PROXY (od liści do roota) ======

REM Liście
start "P2-waw-a:15011" cmd /k java Proxy -port 15011 -server 127.0.0.1 16001 -server 127.0.0.1 16002
start "P3-waw-b1:15013" cmd /k java Proxy -port 15013 -server 127.0.0.1 16003 -server 127.0.0.1 16004
start "P3-krk-a1:15022" cmd /k java Proxy -port 15022 -server 127.0.0.1 16007
start "P3-gdn-a1:15032" cmd /k java Proxy -port 15032 -server 127.0.0.1 16009 -server 127.0.0.1 16010

REM Środek
start "P2-waw-b:15012" cmd /k java Proxy -port 15012 -server 127.0.0.1 15013
start "P2-krk-a:15021" cmd /k java Proxy -port 15021 -server 127.0.0.1 16005 -server 127.0.0.1 16006 -server 127.0.0.1 15022
start "P2-gdn-a:15031" cmd /k java Proxy -port 15031 -server 127.0.0.1 15032 -server 127.0.0.1 16011

REM Poziom P1
start "P1-waw:15010" cmd /k java Proxy -port 15010 -server 127.0.0.1 15011 -server 127.0.0.1 15012
start "P1-krk:15020" cmd /k java Proxy -port 15020 -server 127.0.0.1 15021
start "P1-gdn:15030" cmd /k java Proxy -port 15030 -server 127.0.0.1 16008 -server 127.0.0.1 15031

REM Root
start "P0-root:15000" cmd /k java Proxy -port 15000 -server 127.0.0.1 15010 -server 127.0.0.1 15020 -server 127.0.0.1 15030
