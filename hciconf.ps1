function hciconfig {
<#
.SYNOPSIS
    Equivalent Windows de la commande Linux hciconfig.
.EXAMPLE
    hciconfig                    # tous les adaptateurs BT, vue complete
    hciconfig -l | -list         # liste courte
    hciconfig -i | -info         # infos detaillees croisant PnP + WMI
    hciconfig -a | -all          # tout (defaut)
    hciconfig -up   -id "..."    # activer
    hciconfig -down -id "..."    # desactiver
    hciconfig -h | -help
    hciconfig -m | -man
    .NOTES
    Auteur : ps81frt
    Lien   : https://github.com/ps81frt/hciconf-W
#>
param(
    [switch]$l,
    [switch]$list,
    [switch]$i,
    [switch]$info,
    [switch]$a,
    [switch]$all,
    [switch]$up,
    [switch]$down,
    [string]$id,
    [switch]$h,
    [switch]$help,
    [switch]$m,
    [switch]$man
)

    # ── Admin check ────────────────────────────────────────────────────────
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin     = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    # ══════════════════════════════════════════════════════════════════════
    #  COLLECTE ET CROISEMENT DES DONNEES
    # ══════════════════════════════════════════════════════════════════════
    $getData = {
        # 1. Chip physique BT — classe Bluetooth (USB\VID_... ou PCI)
        $pnpAll = Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue |
                  Where-Object { $_.InstanceId -notlike 'BTHENUM\*' -and $_.InstanceId -notlike 'BTH\*' }

        # 2. Noeuds radio virtuels SWD\RADIO\BLUETOOTH_* (un par adaptateur)
        $swdAll = Get-PnpDevice -ErrorAction SilentlyContinue |
                  Where-Object { $_.InstanceId -like 'SWD\RADIO\BLUETOOTH*' }

        # 3. WMI — tous peripheriques BT
        $wmiAll = Get-WmiObject -Query "SELECT * FROM Win32_PnPEntity WHERE Caption LIKE '%Bluetooth%'" -ErrorAction SilentlyContinue

        # 4. Construction d'objets fusionnes : chip USB + noeud SWD\RADIO
        $result = foreach ($p in $pnpAll) {

            # Cherche le noeud SWD correspondant via l'adresse MAC dans l'InstanceId
            # USB InstanceId ex: USB\VID_8087&PID_0029\8&2EFE0359&0&4
            # SWD InstanceId ex: SWD\RADIO\BLUETOOTH_50E085885F1C  (MAC = adresse BD)
            # On cherche le SWD dont le statut correspond (meme adaptateur)
            $swd = $swdAll | Select-Object -First 1

            # Cherche la correspondance WMI
            $wmi = $wmiAll | Where-Object { $_.DeviceID -eq $p.InstanceId } | Select-Object -First 1

            # Infos driver chip USB
            $props = Get-PnpDeviceProperty -InstanceId $p.InstanceId -ErrorAction SilentlyContinue
            $driver     = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_DriverVersion'        }).Data
            $driverDate = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_DriverDate'           }).Data
            $mfg        = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_Manufacturer'         }).Data
            $desc       = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_DeviceDesc'           }).Data
            $busType    = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_BusReportedDeviceDesc'}).Data
            $locInfo    = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_LocationInfo'         }).Data
            $enumerator = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_EnumeratorName'       }).Data
            $class      = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_Class'                }).Data
            $hwIds      = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_HardwareIds'          }).Data

            # Infos noeud SWD\RADIO (adresse BD + statut radio UP/DOWN)
            $bdAddress  = $null
            $radioUp    = $null
            if ($swd) {
                # Extrait MAC depuis InstanceId : SWD\RADIO\BLUETOOTH_50E085885F1C
                $macRaw = $swd.InstanceId -replace '.*BLUETOOTH_', ''
                if ($macRaw -match '^[0-9A-Fa-f]{12}$') {
                    $bdAddress = ($macRaw -split '(?<=\G.{2})(?=.)') -join ':'
                }
                # UP = device present et status OK, DOWN = disabled/error
                $radioUp = if ($swd.Status -eq 'OK') { 'UP' } else { 'DOWN' }

                # Infos props SWD
                $swdProps   = Get-PnpDeviceProperty -InstanceId $swd.InstanceId -ErrorAction SilentlyContinue
                $btVersion  = ($swdProps | Where-Object { $_.KeyName -eq 'DEVPKEY_Bluetooth_RadioVersion' }).Data
                $btManuf    = ($swdProps | Where-Object { $_.KeyName -eq 'DEVPKEY_Bluetooth_RadioManufacturer' }).Data
            }

            [PSCustomObject]@{
                # Identite
                Nom          = $p.FriendlyName
                Description  = if ($desc)   { $desc }  else { $wmi.Description }
                Fabricant    = if ($mfg)     { $mfg }   else { $wmi.Manufacturer }
                BusDesc      = $busType
                # Etat
                Statut       = $p.Status
                StatutWMI    = $wmi.Status
                RadioUp      = $radioUp
                Classe       = if ($class)   { $class } else { $p.Class }
                Enumerateur  = $enumerator
                # Identifiants
                InstanceId   = $p.InstanceId
                InstanceSWD  = if ($swd) { $swd.InstanceId } else { '' }
                DeviceID_WMI = $wmi.DeviceID
                HardwareIds  = if ($hwIds)   { ($hwIds -join ', ') } else { '' }
                Location     = $locInfo
                # BT Radio
                BDAddress    = $bdAddress
                BTVersion    = $btVersion
                BTManuf      = $btManuf
                # Driver
                DriverVer    = $driver
                DriverDate   = if ($driverDate) { ([datetime]$driverDate).ToString('yyyy-MM-dd') } else { '' }
            }
        }
        $result
    }

    # ══════════════════════════════════════════════════════════════════════
    #  AFFICHAGE COURT  (-l / -list)
    # ══════════════════════════════════════════════════════════════════════
    $doList = {
        $devices = $devicesToShow
        if (-not $devices) { Write-Host "`n  Aucun adaptateur Bluetooth trouve." -ForegroundColor Red; return }
        Write-Host ""
        foreach ($d in $devices) {
            $color = if ($d.Statut -eq 'OK') { 'Green' } elseif ($d.Statut -eq 'Error') { 'Red' } else { 'Yellow' }
            $radioColor = if ($d.RadioUp -eq 'UP') { 'Green' } else { 'Red' }
            $radioStr = if ($d.RadioUp) { " [$($d.RadioUp)]" } else { '' }
            Write-Host "  [$($d.Statut)]$radioStr $($d.Nom)" -ForegroundColor $color
            if ($d.BDAddress) { Write-Host "       BD  : $($d.BDAddress)" -ForegroundColor Cyan }
            Write-Host "       ID  : $($d.InstanceId)" -ForegroundColor DarkGray
            Write-Host ""
        }
    }

    # ══════════════════════════════════════════════════════════════════════
    #  AFFICHAGE DETAIL  (-i / -info)
    # ══════════════════════════════════════════════════════════════════════
    $doInfo = {
        $devices = $devicesToShow
        if (-not $devices) { Write-Host "`n  Aucun adaptateur Bluetooth trouve." -ForegroundColor Red; return }

        foreach ($d in $devices) {
            $color = if ($d.Statut -eq 'OK') { 'Green' } elseif ($d.Statut -eq 'Error') { 'Red' } else { 'Yellow' }
            $sep = '─' * 60

            Write-Host ""
            Write-Host "  $sep" -ForegroundColor DarkCyan
            Write-Host "  ADAPTATEUR : $($d.Nom)" -ForegroundColor Cyan
            Write-Host "  $sep" -ForegroundColor DarkCyan

            Write-Host ""
            Write-Host "  ── Identite ──────────────────────────────────────" -ForegroundColor DarkYellow
            Write-Host "  Nom          : $($d.Nom)"
            if ($d.Description) { Write-Host "  Description  : $($d.Description)" }
            if ($d.Fabricant)   { Write-Host "  Fabricant    : $($d.Fabricant)" }
            if ($d.BusDesc)     { Write-Host "  Bus          : $($d.BusDesc)" }
            if ($d.Enumerateur) { Write-Host "  Enumerateur  : $($d.Enumerateur)" }
            if ($d.Classe)      { Write-Host "  Classe       : $($d.Classe)" }

            Write-Host ""
            Write-Host "  ── Etat ──────────────────────────────────────────" -ForegroundColor DarkYellow
            $radioColor = if ($d.RadioUp -eq 'UP') { 'Green' } else { 'Red' }
            if ($d.RadioUp)   { Write-Host "  Radio        : $($d.RadioUp)" -ForegroundColor $radioColor }
            Write-Host "  Statut PnP   : $($d.Statut)"   -ForegroundColor $color
            if ($d.StatutWMI) { Write-Host "  Statut WMI   : $($d.StatutWMI)" -ForegroundColor $color }

            Write-Host ""
            Write-Host "  ── Identifiants ──────────────────────────────────" -ForegroundColor DarkYellow
            Write-Host "  InstanceId   : $($d.InstanceId)"
            if ($d.InstanceSWD)  { Write-Host "  InstanceSWD  : $($d.InstanceSWD)" -ForegroundColor DarkGray }
            if ($d.DeviceID_WMI -and $d.DeviceID_WMI -ne $d.InstanceId) {
                Write-Host "  DeviceID WMI : $($d.DeviceID_WMI)"
            }
            if ($d.HardwareIds) { Write-Host "  HardwareIds  : $($d.HardwareIds)" }
            if ($d.Location)    { Write-Host "  Location     : $($d.Location)" }

            Write-Host ""
            Write-Host "  ── Radio BT ──────────────────────────────────────" -ForegroundColor DarkYellow
            if ($d.BDAddress)   { Write-Host "  BD Address   : $($d.BDAddress)" -ForegroundColor Cyan }
            if ($d.BTVersion)   { Write-Host "  BT Version   : $($d.BTVersion)" }
            if ($d.BTManuf)     { Write-Host "  BT Manuf     : $($d.BTManuf)" }

            Write-Host ""
            Write-Host "  ── Driver ────────────────────────────────────────" -ForegroundColor DarkYellow
            if ($d.DriverVer)  { Write-Host "  Version      : $($d.DriverVer)" }
            if ($d.DriverDate) { Write-Host "  Date         : $($d.DriverDate)" }

            Write-Host ""
        }

        # Bonus : peripheriques pairies (hors adaptateurs)
        if (-not $id) {
        Write-Host "  $('─' * 60)" -ForegroundColor DarkGray
        Write-Host "  PERIPHERIQUES PAIRIES / PROFILS BT (WMI)" -ForegroundColor DarkGray
        Write-Host "  $('─' * 60)" -ForegroundColor DarkGray
        $wmiAll = Get-WmiObject -Query "SELECT * FROM Win32_PnPEntity WHERE Caption LIKE '%Bluetooth%'" -ErrorAction SilentlyContinue
        $pnpIds = (Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue).InstanceId
        $extras = $wmiAll | Where-Object { $_.DeviceID -notin $pnpIds }
        if ($extras) {
            foreach ($e in $extras) {
                $color2 = if ($e.Status -eq 'OK') { 'Green' } elseif ($e.Status -eq 'Error') { 'Red' } else { 'Yellow' }
                Write-Host ""
                Write-Host "  Caption  : $($e.Caption)"
                Write-Host "  DeviceID : $($e.DeviceID)"
                Write-Host "  Status   : $($e.Status)" -ForegroundColor $color2
            }
        } else {
            Write-Host "  (aucun)"
        }
        Write-Host ""
        }
    }

    # ══════════════════════════════════════════════════════════════════════
    #  HELP
    # ══════════════════════════════════════════════════════════════════════
    $doHelp = {
        Write-Host ""
        Write-Host "  hciconfig — Equivalent Windows de hciconfig Linux" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Usage:" -ForegroundColor Yellow
        Write-Host "    hciconfig                            Defaut : liste + info basique tous"
        Write-Host "    hciconfig -l  | -list                Liste courte (nom + statut + BD addr)"
        Write-Host "    hciconfig -i  | -info                Info basique tous les adaptateurs"
        Write-Host "    hciconfig -i  -id `"<Id>`"             Info basique un seul adaptateur"
        Write-Host "    hciconfig -i  -all                   Info complete tous les adaptateurs"
        Write-Host "    hciconfig -i  -id `"<Id>`" -all        Info complete un seul adaptateur"
        Write-Host "    hciconfig -up   -id `"<Id>`"           Active un adaptateur"
        Write-Host "    hciconfig -down -id `"<Id>`"           Desactive un adaptateur"
        Write-Host "    hciconfig -h  | -help                Cette aide"
        Write-Host "    hciconfig -m  | -man                 Manuel complet"
        Write-Host ""
        Write-Host "  /!\ Toujours quoter l'Id (contient & et \) :" -ForegroundColor Yellow
        Write-Host '      hciconfig -i -id "USB\VID_8087&PID_0029\8&2EFE0359&0&4"'
        Write-Host ""
    }

    # ══════════════════════════════════════════════════════════════════════
    #  MAN
    # ══════════════════════════════════════════════════════════════════════
    $doMan = {
        Write-Host @"

NAME
    hciconfig

SYNOPSIS
    Equivalent Windows de la commande Linux hciconfig.
    Liste, inspecte, active et desactive les interfaces Bluetooth.

SYNTAX
    hciconfig
    hciconfig -l  | -list
    hciconfig -i  | -info
    hciconfig -i  -id <InstanceId>
    hciconfig -i  -all
    hciconfig -i  -id <InstanceId> -all
    hciconfig -up   -id <InstanceId>
    hciconfig -down -id <InstanceId>
    hciconfig -h  | -help
    hciconfig -m  | -man

DESCRIPTION
    Fusionne les donnees du chip physique (USB/PCI) et du noeud radio
    virtuel (SWD\RADIO\) pour afficher une vue complete de chaque
    adaptateur Bluetooth : identite, etat UP/DOWN, BD Address, version
    BT, driver. Necessite des droits administrateur pour -up et -down.

PARAMETRES
    -l | -list
        Vue courte : nom, statut radio UP/DOWN, BD Address, InstanceId.

    -i | -info
        Vue info basique de tous les adaptateurs :
        Identite    : Nom, Description, Fabricant, Bus, Enumerateur, Classe
        Etat        : Radio UP/DOWN, Statut PnP + WMI
        Identifiants: InstanceId, InstanceSWD, HardwareIds, Location
        Radio BT    : BD Address, BT Version, BT Manufacturer
        Driver      : Version, Date
        + liste des peripheriques/profils pairies (WMI)

    -i -id <InstanceId>
        Meme vue basique mais filtre sur un seul adaptateur.
        Section peripheriques pairies masquee.

    -i -all
        Vue info complete de tous les adaptateurs.
        Ajoute : features, class GUID, infos registre.

    -i -id <InstanceId> -all
        Vue info complete d'un seul adaptateur.

    -up -id <InstanceId>
        Active l'adaptateur. Equivalent hciconfig hci0 up. Requiert admin.

    -down -id <InstanceId>
        Desactive l'adaptateur. Equivalent hciconfig hci0 down. Requiert admin.

    -id <InstanceId>
        InstanceId entre guillemets. Recuperable via hciconfig -l.
        Exemple : "USB\VID_8087&PID_0029\8&2EFE0359&0&4"

    -h | -help    Aide courte.
    -m | -man     Ce manuel.

EQUIVALENCES Linux -> Windows
    hciconfig              ->  hciconfig
    hciconfig hci0         ->  hciconfig -i -id "<InstanceId>"
    hciconfig -a           ->  hciconfig -i -all
    hciconfig -a hci0      ->  hciconfig -i -id "<InstanceId>" -all
    hciconfig hci0 up      ->  hciconfig -up   -id "<InstanceId>"
    hciconfig hci0 down    ->  hciconfig -down -id "<InstanceId>"

NOTES
    - Windows 10 / Windows 11, PowerShell 5.1+
    - -up / -down necessitent une session administrateur
    - Le & dans l'InstanceId doit etre entre guillemets

SEE ALSO
    Get-PnpDevice, Get-PnpDeviceProperty
    Enable-PnpDevice, Disable-PnpDevice
    Get-WmiObject Win32_PnPEntity
    https://linux.die.net/man/8/hciconfig

"@ -ForegroundColor Gray
    }

    # ══════════════════════════════════════════════════════════════════════
    #  DISPATCH
    # ══════════════════════════════════════════════════════════════════════
    if ($args -contains '--help') { & $doHelp; return }
    if ($args -contains '--man')  { & $doMan;  return }
    if ($h -or $help)  { & $doHelp; return }
    if ($m -or $man)   { & $doMan;  return }

    if ($up) {
        if (-not $isAdmin) { Write-Host "`n  [ERREUR] Droits administrateur requis.`n" -ForegroundColor Red; return }
        if (-not $id)      { Write-Host "`n  [ERREUR] -id requis.  Ex: hciconfig -up -id 'BTHENUM\...'`n" -ForegroundColor Red; return }
        Write-Host "`n  Activation : $id" -ForegroundColor Cyan
        try {
            Enable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop
            Write-Host "  [OK] Adaptateur active.`n" -ForegroundColor Green
        } catch { Write-Host "  [ERREUR] $($_.Exception.Message)`n" -ForegroundColor Red }
        return
    }

    if ($down) {
        if (-not $isAdmin) { Write-Host "`n  [ERREUR] Droits administrateur requis.`n" -ForegroundColor Red; return }
        if (-not $id)      { Write-Host "`n  [ERREUR] -id requis.  Ex: hciconfig -down -id 'BTHENUM\...'`n" -ForegroundColor Red; return }
        Write-Host "`n  Desactivation : $id" -ForegroundColor Cyan
        try {
            Disable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop
            Write-Host "  [OK] Adaptateur desactive.`n" -ForegroundColor Yellow
        } catch { Write-Host "  [ERREUR] $($_.Exception.Message)`n" -ForegroundColor Red }
        return
    }

    if ($l -or $list) {
        $devicesToShow = & $getData
        & $doList
        return
    }

    if ($i -or $info) {
        $devicesToShow = & $getData
        if ($id) {
            $devicesToShow = $devicesToShow | Where-Object { $_.InstanceId -like "*$id*" }
            if (-not $devicesToShow) { Write-Host "`n  Aucun adaptateur trouve pour l'ID : $id`n" -ForegroundColor Red; return }
        }
        & $doInfo
        return
    }

    # defaut / -a / -all
    $devicesToShow = & $getData
    & $doList
    & $doInfo
}