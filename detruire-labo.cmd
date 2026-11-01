@echo off
rem  TP 1 -- Supprime les quatre machines du laboratoire.
rem  L'OVA et le modele importe sont conserves : un remontage prend 2 min.
setlocal
title Laboratoire MediSud -- suppression

set "VBOX="
if exist "%ProgramFiles%\Oracle\VirtualBox\VBoxManage.exe" set "VBOX=%ProgramFiles%\Oracle\VirtualBox\VBoxManage.exe"
if not defined VBOX where /q VBoxManage.exe && set "VBOX=VBoxManage.exe"
if not defined VBOX ( echo VirtualBox introuvable & pause & exit /b 1 )

echo Vont etre SUPPRIMEES, avec leurs disques :
echo    srv-lb  srv-app-a  srv-app-b  srv-db-1
echo.
set /p REPONSE=Confirmer ? (tapez oui) :
if /i not "%REPONSE%"=="oui" ( echo annule & pause & exit /b 0 )

for %%M in (srv-lb srv-app-a srv-app-b srv-db-1) do (
  "%VBOX%" controlvm %%M poweroff >nul 2>&1
  timeout /t 1 /nobreak >nul
  "%VBOX%" unregistervm %%M --delete >nul 2>&1
  echo    %%M supprimee
)
echo.
echo Laboratoire supprime. Relancez monter-labo.cmd pour le remonter.
pause
