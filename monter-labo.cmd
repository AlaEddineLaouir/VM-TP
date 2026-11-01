@echo off
rem ===================================================================
rem  TP 1 -- Monte le laboratoire MediSud : quatre machines, pretes.
rem
rem    Double-cliquez sur ce fichier.
rem
rem    srv-lb     10.10.12.40   repartiteur HAProxy
rem    srv-app-a  10.10.12.41   instance A du Portail
rem    srv-app-b  10.10.12.42   instance B du Portail
rem    srv-db-1   10.10.12.51   PostgreSQL (base portail deja creee)
rem
rem  Compte sur chaque machine : medisud / medisud  (sudo sans mot de passe)
rem ===================================================================
setlocal enabledelayedexpansion
title Laboratoire MediSud -- TP 1

set "RACINE=%~dp0"
set "SEEDS=%RACINE%seeds"
set "MODELE_VM=modele-medisud"
set "OVA=%RACINE%modele-amd64.ova"

rem --- VBoxManage n'est pas dans le PATH par defaut sous Windows -----
set "VBOX="
if exist "%ProgramFiles%\Oracle\VirtualBox\VBoxManage.exe" set "VBOX=%ProgramFiles%\Oracle\VirtualBox\VBoxManage.exe"
if not defined VBOX if exist "%ProgramFiles(x86)%\Oracle\VirtualBox\VBoxManage.exe" set "VBOX=%ProgramFiles(x86)%\Oracle\VirtualBox\VBoxManage.exe"
if not defined VBOX where /q VBoxManage.exe && set "VBOX=VBoxManage.exe"
if not defined VBOX (
  echo.
  echo ECHEC : VirtualBox est introuvable.
  echo         Installez-le, puis relancez ce fichier.
  pause & exit /b 1
)

rem --- 1. Le modele, importe une seule fois --------------------------
"%VBOX%" list vms | findstr /c:"\"%MODELE_VM%\"" >nul
if errorlevel 1 (
  if not exist "%OVA%" (
    echo.
    echo ECHEC : modele-amd64.ova introuvable a cote de ce script.
    echo         Copiez tout le dossier labo\ depuis la cle USB.
    pause & exit /b 1
  )
  echo.
  echo == Import du modele ^(~1 min, une seule fois^)
  "%VBOX%" import "%OVA%" --vsys 0 --vmname "%MODELE_VM%"
  if errorlevel 1 ( echo ECHEC a l'import & pause & exit /b 1 )
)

rem --- 2. Le reseau du laboratoire -----------------------------------
rem Sous Windows : un "host-only adapter". On ne lit JAMAIS le message de
rem creation (il est traduit sur un Windows francais) : on compare la liste
rem des adaptateurs avant et apres pour trouver le nouveau.
echo.
echo == Reseau du laboratoire 10.10.12.0/24

rem Droits : hostonlyif create exige souvent une invite "administrateur".
net session >nul 2>&1
if errorlevel 1 (
  echo    [!] Cette fenetre n'est PAS administrateur. Si la creation echoue,
  echo        relancez par clic droit ^> "Executer en tant qu'administrateur".
)

set "ADAPT="

rem 2a. Un adaptateur a-t-il deja l'adresse 10.10.12.1 ?
call :chercher_adaptateur
if defined ADAPT goto :adaptateur_pret

rem 2b. Le nom retenu lors d'une execution precedente est-il encore valable ?
if exist "%RACINE%.adaptateur" (
  set /p ADAPT=<"%RACINE%.adaptateur"
  "%VBOX%" list hostonlyifs | findstr /c:"!ADAPT!" >nul || set "ADAPT="
)
if defined ADAPT goto :configurer_adaptateur

rem 2c. Sinon on en cree un, et on le repere par difference de listes
"%VBOX%" list hostonlyifs | findstr /b /c:"Name:" > "%TEMP%\hoif-avant.txt" 2>nul
"%VBOX%" hostonlyif create >nul 2>&1
"%VBOX%" list hostonlyifs | findstr /b /c:"Name:" > "%TEMP%\hoif-apres.txt" 2>nul
for /f "usebackq tokens=1,* delims=:" %%A in (`findstr /v /l /g:"%TEMP%\hoif-avant.txt" "%TEMP%\hoif-apres.txt"`) do (
  for /f "tokens=*" %%V in ("%%B") do set "ADAPT=%%V"
)
if not defined ADAPT (
  rem Dernier recours : prendre le dernier adaptateur de la liste
  for /f "usebackq tokens=1,* delims=:" %%A in (`""%VBOX%" list hostonlyifs ^| findstr /b /c:"Name:""`) do (
    for /f "tokens=*" %%V in ("%%B") do set "ADAPT=%%V"
  )
)
if not defined ADAPT (
  echo.
  echo ECHEC : aucun adaptateur host-only disponible.
  echo.
  echo    A faire une seule fois, dans VirtualBox :
  echo       Fichier ^> Outils ^> Gestionnaire de reseau
  echo       onglet "Reseaux hote uniquement" ^> Creer
  echo       Adresse IPv4 : 10.10.12.1   Masque : 255.255.255.0
  echo       Serveur DHCP : decoche
  echo.
  echo    Puis relancez ce fichier.
  pause & exit /b 1
)
> "%RACINE%.adaptateur" echo !ADAPT!

:configurer_adaptateur
"%VBOX%" hostonlyif ipconfig "!ADAPT!" --ip 10.10.12.1 --netmask 255.255.255.0
if errorlevel 1 (
  echo.
  echo ECHEC : impossible d'attribuer 10.10.12.1 a "!ADAPT!".
  echo         Relancez cette fenetre en tant qu'administrateur.
  pause & exit /b 1
)

:adaptateur_pret
echo    adaptateur : !ADAPT!

rem --- 3. Les quatre machines ----------------------------------------
call :machine srv-lb    10.10.12.40 080027001240 080027010040 1024 2240
call :machine srv-app-a 10.10.12.41 080027001241 080027010041 1024 2241
call :machine srv-app-b 10.10.12.42 080027001242 080027010042 1024 2242
call :machine srv-db-1  10.10.12.51 080027001251 080027010051 1536 2251

rem --- 4. Attendre que le laboratoire reponde ------------------------
echo.
echo == Premier demarrage : nom, adresse, paquets ^(1 a 3 minutes^)
set /a ESSAI=0
:boucle
set "MANQUE="
for %%I in (10.10.12.40 10.10.12.41 10.10.12.42 10.10.12.51) do (
  ping -n 1 -w 1000 %%I | findstr /c:"TTL=" >nul || set "MANQUE=!MANQUE! %%I"
)
if not defined MANQUE goto :etat
set /a ESSAI+=1
if !ESSAI! GEQ 36 goto :etat
echo    en attente de :!MANQUE!
timeout /t 5 /nobreak >nul
goto :boucle

rem Le ping repond des que le reseau est monte, mais cloud-init installe encore
rem les paquets pendant 2 a 3 minutes. On attend PostgreSQL sur srv-db-1 :
rem c'est lui qui prouve que l'installation est terminee.
echo.
echo == Installation des paquets ^(2 a 3 minutes^)
set /a ESSAI=0
:attente_pg
curl.exe -s -o nul --connect-timeout 2 http://10.10.12.51:5432 >nul 2>&1
if not errorlevel 7 goto :etat
set /a ESSAI+=1
if !ESSAI! GEQ 48 goto :etat
echo    PostgreSQL pas encore pret sur srv-db-1...
timeout /t 5 /nobreak >nul
goto :attente_pg

:etat
echo.
echo == Etat du laboratoire
for %%I in (10.10.12.40 10.10.12.41 10.10.12.42 10.10.12.51) do (
  ping -n 1 -w 1000 %%I | findstr /c:"TTL=" >nul && (echo    %%I  repond) || (echo    %%I  MUETTE)
)
echo.
echo    Compte sur chaque machine : medisud / medisud
echo    Se connecter :  ssh medisud@10.10.12.41
echo.
echo    Une machine MUETTE au-dela de 3 minutes installe sans doute encore
echo    ses paquets : relancez ce fichier, il reprend sans rien casser.
echo.
pause
exit /b 0

rem ===================== sous-programmes =============================
:chercher_adaptateur
rem Parcourt "list hostonlyifs" et retient le nom de l'adaptateur dont
rem l'adresse est deja 10.10.12.1. Insensible a la langue de Windows.
set "ADAPT="
set "NOMCOURANT="
for /f "usebackq tokens=1,* delims=:" %%A in (`""%VBOX%" list hostonlyifs"`) do (
  set "CLE=%%A"
  set "VAL=%%B"
  for /f "tokens=*" %%V in ("!VAL!") do set "VAL=%%V"
  if /i "!CLE!"=="Name" set "NOMCOURANT=!VAL!"
  if /i "!CLE!"=="IPAddress" if "!VAL!"=="10.10.12.1" set "ADAPT=!NOMCOURANT!"
)
goto :eof

:machine
set "NOM=%~1"
set "IP=%~2"
set "MAC_LAB=%~3"
set "MAC_NAT=%~4"
set "RAM=%~5"
set "PORT=%~6"

"%VBOX%" list vms | findstr /c:"\"%NOM%\"" >nul
if not errorlevel 1 (
  echo    %NOM% existe deja -- ignoree ^(detruire-labo.cmd pour repartir a neuf^)
  goto :eof
)
if not exist "%SEEDS%\seed-%NOM%.iso" (
  echo ECHEC : CD cloud-init manquant : seeds\seed-%NOM%.iso
  pause & exit /b 1
)

echo.
echo == Creation de %NOM% ^(%IP%^)
"%VBOX%" clonevm "%MODELE_VM%" --name "%NOM%" --register >nul

rem Carte 1 = NAT (internet + acces SSH depuis l'hote sur un port dedie)
rem Carte 2 = le reseau du laboratoire, ou vit l'adresse 10.10.12.x
rem --nictype virtio est OBLIGATOIRE : l'image cloud Debian a un noyau allege,
rem SANS le pilote e1000 que VirtualBox propose par defaut. Avec e1000, la
rem machine demarre sans AUCUNE interface reseau.
"%VBOX%" modifyvm "%NOM%" --memory %RAM% --cpus 1 ^
  --nic1 nat --nictype1 virtio --mac-address1 %MAC_NAT% ^
  --natpf1 "ssh,tcp,127.0.0.1,%PORT%,,22" ^
  --nic2 hostonly --host-only-adapter2 "!ADAPT!" --nictype2 virtio --mac-address2 %MAC_LAB%

rem Le CD cloud-init pose le nom, l'adresse fixe et le compte au 1er demarrage
"%VBOX%" storageattach "%NOM%" --storagectl virtio --port 1 --device 0 ^
  --type dvddrive --medium "%SEEDS%\seed-%NOM%.iso" --forceunmount

"%VBOX%" startvm "%NOM%" --type headless >nul
goto :eof
