<#
    TP 2 -- Construction complete de la topologie MediSud.
    A executer SUR SRV-DC01, dans une console PowerShell ADMINISTRATEUR.

        powershell -ExecutionPolicy Bypass -File .\tp2-construction.ps1

    Prerequis : l'annuaire de la seance 1 (OU=MEDISUD, OU=Sites, OU=MRS,
    OU=Ressources, les 3 GG-MRS-* et les 2 DL-Patients-*).
    Sinon, lancez d'abord tp1-reconstruction.ps1.

    REJOUABLE : chaque objet deja present est signale et ignore, pas recree.
    Vous pouvez donc le relancer apres avoir corrige une erreur.
#>
#Requires -RunAsAdministrator
Import-Module ActiveDirectory -ErrorAction Stop

$racine  = "DC=medisud,DC=local"
$medisud = "OU=MEDISUD,$racine"
$sitesOU = "OU=Sites,$medisud"
$ressOU  = "OU=Ressources,$medisud"

function Titre($t) { Write-Host "`n== $t" -ForegroundColor Cyan }
function Ok($t)    { Write-Host "   + $t" -ForegroundColor Green }
function Deja($t)  { Write-Host "   . $t (deja present)" -ForegroundColor DarkGray }

# --- Garde-fou : la seance 1 est-elle bien en place ? -----------------------
foreach ($dn in @($medisud, $sitesOU, $ressOU)) {
    if (-not (Get-ADOrganizationalUnit -Filter * -SearchBase $dn -SearchScope Base -ErrorAction SilentlyContinue)) {
        throw "Introuvable : $dn . Lancez d'abord tp1-reconstruction.ps1"
    }
}

# --- Petites fonctions idempotentes ----------------------------------------
function New-OUSiAbsente($nom, $chemin) {
    $dn = "OU=$nom,$chemin"
    if (Get-ADOrganizationalUnit -Filter * -SearchBase $dn -SearchScope Base -ErrorAction SilentlyContinue) {
        Deja "OU=$nom"
    } else {
        New-ADOrganizationalUnit -Name $nom -Path $chemin
        Ok "OU=$nom"
    }
}

function New-GroupeSiAbsent($nom, $etendue, $chemin) {
    if (Get-ADGroup -Filter "Name -eq '$nom'" -ErrorAction SilentlyContinue) {
        Deja $nom
    } else {
        New-ADGroup -Name $nom -GroupScope $etendue -GroupCategory Security -Path $chemin
        Ok "$nom ($etendue)"
    }
}

# --- 1. Les sites manquants et leurs groupes de role ------------------------
# MRS existe depuis la seance 1 : il n'est pas dans cette table.
Titre "Sites et groupes de role"
$sites = [ordered]@{
    "MTP" = @("Medecins","Infirmiers","Secretaires","Comptabilite")
    "TLS" = @("Laborantins","Secretaires")
    "PRP" = @("Medecins","Secretaires")
}
foreach ($code in $sites.Keys) {
    New-OUSiAbsente $code $sitesOU
    $ouSite = "OU=$code,$sitesOU"
    foreach ($tiroir in "Utilisateurs","Ordinateurs","Groupes") {
        New-OUSiAbsente $tiroir $ouSite
    }
    foreach ($role in $sites[$code]) {
        New-GroupeSiAbsent "GG-$code-$role" "Global" "OU=Groupes,$ouSite"
    }
}

# --- 2. Les groupes transverses et le groupe de delegation ------------------
Titre "Groupes transverses et delegation"
New-OUSiAbsente "Groupes-Transverses" $medisud
foreach ($role in "Direction","Informatique") {
    New-GroupeSiAbsent "GG-$role" "Global" "OU=Groupes-Transverses,$medisud"
}
New-GroupeSiAbsent "GG-PRP-Referent" "Global" "OU=Groupes,OU=PRP,$sitesOU"

# --- 3. Les groupes de ressource manquants ----------------------------------
# DL-Patients-RW et DL-Patients-R existent depuis la seance 1.
# Direction, Public et Informatique n'ont QU'UN seul niveau de droit dans la
# matrice : un seul groupe chacun. 9 au total, pas 12.
Titre "Groupes de ressource"
$dl = @("Labo-RW","Labo-R","Compta-RW","Compta-R",
        "Direction-RW","Public-RW","Informatique-RW")
foreach ($d in $dl) { New-GroupeSiAbsent "DL-$d" "DomainLocal" $ressOU }

# --- 4. Le cablage GG -> DL : c'est la matrice de droits, transposee --------
Titre "Cablage GG -> DL"
$tousRoles = @("GG-MTP-Medecins","GG-MRS-Medecins","GG-PRP-Medecins",
               "GG-MTP-Infirmiers","GG-MRS-Infirmiers","GG-TLS-Laborantins",
               "GG-MTP-Secretaires","GG-MRS-Secretaires","GG-TLS-Secretaires",
               "GG-PRP-Secretaires","GG-MTP-Comptabilite",
               "GG-Direction","GG-Informatique")
$medecinsEtInfirmiers = @("GG-MTP-Medecins","GG-MRS-Medecins","GG-PRP-Medecins",
                          "GG-MTP-Infirmiers","GG-MRS-Infirmiers")
$secretaires = @("GG-MTP-Secretaires","GG-MRS-Secretaires",
                 "GG-TLS-Secretaires","GG-PRP-Secretaires")

$cablage = [ordered]@{
    "DL-Patients-RW"     = $medecinsEtInfirmiers
    "DL-Patients-R"      = @("GG-TLS-Laborantins") + $secretaires
    "DL-Labo-RW"         = @("GG-TLS-Laborantins")
    "DL-Labo-R"          = $medecinsEtInfirmiers
    "DL-Compta-RW"       = @("GG-MTP-Comptabilite")
    "DL-Compta-R"        = @("GG-Direction")
    "DL-Direction-RW"    = @("GG-Direction")
    "DL-Informatique-RW" = @("GG-Informatique")
    "DL-Public-RW"       = $tousRoles
}
foreach ($groupeDL in $cablage.Keys) {
    $dejaMembres = @(Get-ADGroupMember $groupeDL -ErrorAction SilentlyContinue |
                     Select-Object -ExpandProperty Name)
    $aAjouter = $cablage[$groupeDL] | Where-Object { $_ -notin $dejaMembres }
    if ($aAjouter) {
        Add-ADGroupMember -Identity $groupeDL -Members $aAjouter
        Ok "$groupeDL <- $($aAjouter.Count) groupe(s)"
    } else {
        Deja "$groupeDL (cablage complet)"
    }
}

# --- 5. Les partages et les permissions NTFS --------------------------------
# Patients existe depuis la seance 1.
Titre "Partages et permissions NTFS"
foreach ($p in "Labo","Compta","Direction","Public","Informatique") {
    $chemin = "C:\Partages\$p"
    New-Item -Path $chemin -ItemType Directory -Force | Out-Null
    if (Get-SmbShare -Name $p -ErrorAction SilentlyContinue) {
        Deja "partage $p"
    } else {
        New-SmbShare -Name $p -Path $chemin -FullAccess "Everyone" | Out-Null
        Ok "partage $p"
    }
}

# M  = Modification (RW)   RX = Lecture et execution (R)
$perm = [ordered]@{
    "Patients"     = @(@("DL-Patients-RW","M"), @("DL-Patients-R","RX"))
    "Labo"         = @(@("DL-Labo-RW","M"),     @("DL-Labo-R","RX"))
    "Compta"       = @(@("DL-Compta-RW","M"),   @("DL-Compta-R","RX"))
    "Direction"    = @(,@("DL-Direction-RW","M"))
    "Public"       = @(,@("DL-Public-RW","M"))
    "Informatique" = @(,@("DL-Informatique-RW","M"))
}
foreach ($p in $perm.Keys) {
    foreach ($regle in $perm[$p]) {
        # (OI)(CI) : l'heritage descend sur les sous-dossiers ET les fichiers
        icacls "C:\Partages\$p" /grant "MEDISUD\$($regle[0]):(OI)(CI)$($regle[1])" | Out-Null
    }
    Ok "permissions sur $p"
}

# --- 6. Verification ---------------------------------------------------------
Titre "Verification"
$nbDL = (Get-ADGroup -Filter "Name -like 'DL-*'").Count
$nbGG = (Get-ADGroup -Filter "Name -like 'GG-*'").Count
Write-Host "   groupes DL- : $nbDL   (attendu 9)"
Write-Host "   groupes GG- : $nbGG   (attendu 14, dont GG-PRP-Referent)"
Write-Host ""
Write-Host "   Controle utile : qui peut ecrire dans Labo ?" -ForegroundColor Yellow
Get-ADGroupMember "DL-Labo-RW" -Recursive | Select-Object Name, objectClass
