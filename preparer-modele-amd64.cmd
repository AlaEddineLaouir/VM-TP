@echo off
rem ===================================================================
rem  FORMATEUR -- fabrique modele-amd64.ova sur un PC Windows x86-64.
rem
rem  A lancer UNE FOIS. Produit le fichier que les etudiants recevront.
rem  Duree : ~5 min (dont le telechargement de 250 Mo).
rem ===================================================================
setlocal
title Fabrication du modele amd64

set "RACINE=%~dp0"
set "TRAVAIL=%RACINE%travail"
set "VM=modele-fabrication"

set "VBOX="
if exist "%ProgramFiles%\Oracle\VirtualBox\VBoxManage.exe" set "VBOX=%ProgramFiles%\Oracle\VirtualBox\VBoxManage.exe"
if not defined VBOX where /q VBoxManage.exe && set "VBOX=VBoxManage.exe"
if not defined VBOX ( echo VirtualBox introuvable & pause & exit /b 1 )

if not exist "%TRAVAIL%" mkdir "%TRAVAIL%"

rem --- 1. L'image cloud Debian 12, amd64 -----------------------------
if not exist "%TRAVAIL%\disk.raw" (
  echo.
  echo == Telechargement de l'image cloud Debian 12 amd64 ^(~250 Mo^)
  curl.exe -L -o "%TRAVAIL%\debian-12-genericcloud-amd64.tar.xz" ^
    https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.tar.xz
  if errorlevel 1 ( echo ECHEC du telechargement & pause & exit /b 1 )
  echo == Extraction
  tar.exe -xJf "%TRAVAIL%\debian-12-genericcloud-amd64.tar.xz" -C "%TRAVAIL%"
)

rem --- 2. Conversion en disque VirtualBox -----------------------------
if not exist "%TRAVAIL%\modele-amd64.vdi" (
  echo == Conversion en disque VirtualBox
  "%VBOX%" convertfromraw "%TRAVAIL%\disk.raw" "%TRAVAIL%\modele-amd64.vdi" --format VDI
  "%VBOX%" modifymedium disk "%TRAVAIL%\modele-amd64.vdi" --resize 8192
)

rem --- 3. La VM modele -------------------------------------------------
rem Une seule carte NAT dans l'OVA : la carte du laboratoire est ajoutee
rem par monter-labo.cmd, qui connait le nom de l'adaptateur local.
"%VBOX%" unregistervm "%VM%" --delete >nul 2>&1
echo == Construction de la machine modele
"%VBOX%" createvm --name "%VM%" --ostype Debian12_64 --register
rem --nictype1 virtio : le noyau cloud de Debian n'a pas le pilote e1000
"%VBOX%" modifyvm "%VM%" --memory 1024 --cpus 1 --vram 16 --audio-driver none --nic1 nat --nictype1 virtio
"%VBOX%" storagectl "%VM%" --name virtio --add virtio-scsi --bootable on
"%VBOX%" storageattach "%VM%" --storagectl virtio --port 0 --device 0 --type hdd --medium "%TRAVAIL%\modele-amd64.vdi"
"%VBOX%" storageattach "%VM%" --storagectl virtio --port 1 --device 0 --type dvddrive --medium emptydrive

rem --- 4. L'export ------------------------------------------------------
if exist "%RACINE%modele-amd64.ova" del "%RACINE%modele-amd64.ova"
echo == Export en OVA ^(~2 min^)
"%VBOX%" export "%VM%" -o "%RACINE%modele-amd64.ova" --vsys 0 --vmname modele-medisud
"%VBOX%" unregistervm "%VM%" --delete

echo.
echo TERMINE : %RACINE%modele-amd64.ova
echo Le dossier travail\ peut etre supprime.
pause
