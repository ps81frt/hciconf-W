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
    hciconfig -i -id "BTHENUMxxxxxxxxx" -all *> monster.txt     #Export.
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
        if (-not ([System.Management.Automation.PSTypeName]'HciConfig.BtRadioNative').Type) {
            try {
                Add-Type -Namespace 'HciConfig' -Name 'BtRadioNative' -MemberDefinition @'
    // BLUETOOTH_FIND_RADIO_PARAMS
    [System.Runtime.InteropServices.StructLayout(
        System.Runtime.InteropServices.LayoutKind.Sequential)]
    public struct BLUETOOTH_FIND_RADIO_PARAMS {
        public uint dwSize;
    }

    // BLUETOOTH_RADIO_INFO  (276 bytes total, cf. SDK bthdef.h)
    [System.Runtime.InteropServices.StructLayout(
        System.Runtime.InteropServices.LayoutKind.Sequential, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    public struct BLUETOOTH_RADIO_INFO {
        public uint   dwSize;
        [System.Runtime.InteropServices.MarshalAs(
            System.Runtime.InteropServices.UnmanagedType.ByValArray, SizeConst = 6)]
        public byte[] address;          // BD_ADDR (6 bytes, LSB first)
        [System.Runtime.InteropServices.MarshalAs(
            System.Runtime.InteropServices.UnmanagedType.ByValTStr, SizeConst = 248)]
        public string szName;           // friendly name (248 chars)
        public uint   ulClassofDevice;
        public ushort lmpSubversion;    // LMP subversion
        public ushort manufacturer;     // manufacturer code
    }
    // NOTE : lmpVersion n'est pas dans BLUETOOTH_RADIO_INFO — on la lit via
    // BluetoothGetDeviceInfo / registry SWD. Mais le manufacturer + subversion
    // permettent de déduire la spec BT quand le registre est vide.
    // Pour LmpVersion on utilise SetupDiGetDeviceProperty DEVPKEY côté SWD,
    // ou on lit le handle radio pour inférer la version via le subversion Intel.

    [System.Runtime.InteropServices.DllImport("bluetoothapis.dll", SetLastError = true)]
    public static extern System.IntPtr BluetoothFindFirstRadio(
        ref BLUETOOTH_FIND_RADIO_PARAMS pbtfrp,
        out System.IntPtr phRadio);

    [System.Runtime.InteropServices.DllImport("bluetoothapis.dll", SetLastError = true)]
    [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
    public static extern bool BluetoothFindNextRadio(
        System.IntPtr hFind,
        out System.IntPtr phRadio);

    [System.Runtime.InteropServices.DllImport("bluetoothapis.dll", SetLastError = true)]
    [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
    public static extern bool BluetoothFindRadioClose(System.IntPtr hFind);

    [System.Runtime.InteropServices.DllImport("bluetoothapis.dll", SetLastError = true)]
    public static extern uint BluetoothGetRadioInfo(
        System.IntPtr hRadio,
        ref BLUETOOTH_RADIO_INFO pRadioInfo);

    [System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
    [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
    public static extern bool CloseHandle(System.IntPtr hObject);
'@ -ErrorAction Stop
            } catch {
                Write-Verbose "[hciconfig] Add-Type BtRadioNative ignoré : $_"
            }
        }
        function Get-BtRadioInfoNative {
            $radios = @()
            $nativeAvailable = ([System.Management.Automation.PSTypeName]'HciConfig.BtRadioNative').Type
            if (-not $nativeAvailable) { return $radios }
            try {
                $params = New-Object HciConfig.BtRadioNative+BLUETOOTH_FIND_RADIO_PARAMS
                $params.dwSize = [System.Runtime.InteropServices.Marshal]::SizeOf($params)
                $hRadio  = [System.IntPtr]::Zero
                $hFind   = [HciConfig.BtRadioNative]::BluetoothFindFirstRadio([ref]$params, [ref]$hRadio)
                if ($hFind -eq [System.IntPtr]::Zero) { return $radios }
                do {
                    $info = New-Object HciConfig.BtRadioNative+BLUETOOTH_RADIO_INFO
                    $info.dwSize = [System.Runtime.InteropServices.Marshal]::SizeOf($info)
                    if ([HciConfig.BtRadioNative]::BluetoothGetRadioInfo($hRadio, [ref]$info) -eq 0) {
                        $macBytes = $info.address[5..0]
                        $bdStr = ($macBytes | ForEach-Object { '{0:X2}' -f $_ }) -join ':'
                        $radios += [PSCustomObject]@{
                            BDAddr       = $bdStr
                            LmpSubversion = $info.lmpSubversion
                            Manufacturer  = $info.manufacturer
                        }
                    }
                    [HciConfig.BtRadioNative]::CloseHandle($hRadio) | Out-Null
                    $hRadio = [System.IntPtr]::Zero
                } while ([HciConfig.BtRadioNative]::BluetoothFindNextRadio($hFind, [ref]$hRadio))
                [HciConfig.BtRadioNative]::BluetoothFindRadioClose($hFind) | Out-Null
            } catch {
                Write-Verbose "[hciconfig] Get-BtRadioInfoNative erreur : $_"
            }
            return $radios
        }

        $nativeRadios = Get-BtRadioInfoNative
        $pnpAll = Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue |
                  Where-Object { $_.InstanceId -notlike 'BTHENUM\*' -and $_.InstanceId -notlike 'BTH\*' -and $_.InstanceId -notlike 'BTHLE\*' }

        $swdAll = Get-PnpDevice -ErrorAction SilentlyContinue |
                  Where-Object { $_.InstanceId -like 'SWD\RADIO\BLUETOOTH*' }

        $wmiAll = Get-WmiObject -Query "SELECT * FROM Win32_PnPEntity WHERE Caption LIKE '%Bluetooth%'" -ErrorAction SilentlyContinue

        $result = foreach ($p in $pnpAll) {

            $swd = $swdAll | Select-Object -First 1

            $wmi = $wmiAll | Where-Object { $_.DeviceID -eq $p.InstanceId } | Select-Object -First 1

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
            $infPath    = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_DriverInfPath'        }).Data
            $infSection = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_DriverInfSection'     }).Data
            $service    = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_Service'              }).Data
            $busNum     = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_BusNumber'            }).Data
            $busAddr    = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_Address'              }).Data
            $uiNum      = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_UINumber'             }).Data

            $bdAddress  = $null
            $radioUp    = $null
            if ($swd) {
                $macRaw = $swd.InstanceId -replace '.*BLUETOOTH_', ''
                if ($macRaw -match '^[0-9A-Fa-f]{12}$') {
                    $bdAddress = ($macRaw -split '(?<=\G.{2})(?=.)') -join ':'
                }
                $radioUp = if ($swd.Status -eq 'OK') { 'UP' } else { 'DOWN' }

                $swdProps   = Get-PnpDeviceProperty -InstanceId $swd.InstanceId -ErrorAction SilentlyContinue
                $btVersion  = ($swdProps | Where-Object { $_.KeyName -eq 'DEVPKEY_Bluetooth_RadioVersion' }).Data
                $btManuf    = ($swdProps | Where-Object { $_.KeyName -eq 'DEVPKEY_Bluetooth_RadioManufacturer' }).Data
            }


            $lmpVersion = $null; $lmpSubVersion = $null; $btSpec = $null; $btFreq = '2.4 GHz (2402-2480 MHz, FHSS)'
            $lmpSpecMap = @{0='1.0b';1='1.1';2='1.2';3='2.0+EDR';4='2.1+EDR';5='3.0+HS';6='4.0';7='4.1';8='4.2';9='5.0';10='5.1';11='5.2';12='5.3';13='5.4'}
            $regCandidates = @(
                "HKLM:\SYSTEM\CurrentControlSet\Enum\$($p.InstanceId)\Device Parameters",
                "HKLM:\SYSTEM\CurrentControlSet\Enum\$($p.InstanceId)\Device Parameters\Bluetooth"
            )
            foreach ($regPath in $regCandidates) {
                if ($null -ne $lmpVersion) { break }
                if (Test-Path $regPath) {
                    $r1 = Get-ItemProperty $regPath -Name 'LmpVersion'    -ErrorAction SilentlyContinue; if ($r1) { $lmpVersion    = $r1.LmpVersion }
                    $r2 = Get-ItemProperty $regPath -Name 'LmpSubversion' -ErrorAction SilentlyContinue; if ($r2) { $lmpSubVersion = $r2.LmpSubversion }
                }
            }
            if ($null -eq $lmpVersion -and $swd) {
                $lmpVersion    = ($swdProps | Where-Object { $_.KeyName -eq 'DEVPKEY_Bluetooth_RadioLmpVersion'    }).Data
                $lmpSubVersion = ($swdProps | Where-Object { $_.KeyName -eq 'DEVPKEY_Bluetooth_RadioLmpSubversion' }).Data
            }
            if ($null -eq $lmpVersion -and $service) {
                $btRegSvc = "HKLM:\SYSTEM\CurrentControlSet\Services\$service\Parameters"
                if (Test-Path $btRegSvc) {
                    $r3 = Get-ItemProperty $btRegSvc -Name 'LmpVersion'    -ErrorAction SilentlyContinue; if ($r3) { $lmpVersion    = $r3.LmpVersion }
                    $r4 = Get-ItemProperty $btRegSvc -Name 'LmpSubversion' -ErrorAction SilentlyContinue; if ($r4) { $lmpSubVersion = $r4.LmpSubversion }
                }
            }
            if ($null -ne $lmpVersion) { $btSpec = $lmpSpecMap[[int]$lmpVersion] }


            if ($null -eq $lmpVersion -and $nativeRadios -and $bdAddress) {
                $matchedNative = $nativeRadios | Where-Object { $_.BDAddr -eq $bdAddress } | Select-Object -First 1
                if ($matchedNative) {
                    if ($null -eq $lmpSubVersion) { $lmpSubVersion = $matchedNative.LmpSubversion }

                    if ($null -eq $lmpVersion -and $matchedNative.Manufacturer -eq 0x0002) {
                        $inferredLmp = [int](($matchedNative.LmpSubversion -band 0xFF00) -shr 8)
                        if ($inferredLmp -gt 0 -and $lmpSpecMap.ContainsKey($inferredLmp)) {
                            $lmpVersion = $inferredLmp
                            $btSpec     = $lmpSpecMap[$inferredLmp] + ' (infere Intel P/Invoke)'
                        }
                    }

                }
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
                LmpVersion   = $lmpVersion
                LmpSubVer    = $lmpSubVersion
                BTSpec       = $btSpec
                BTFreq       = $btFreq
                # Driver
                DriverVer    = $driver
                DriverDate   = if ($driverDate) { ([datetime]$driverDate).ToString('yyyy-MM-dd') } else { '' }
                InfPath      = $infPath
                InfSection   = $infSection
                Service      = $service
                BusNumber    = $busNum
                BusAddress   = $busAddr
                UINumber     = $uiNum
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
            $radioStr = if ($d.RadioUp) { " [$($d.RadioUp)]" } else { '' }
            Write-Host "  [$($d.Statut)]$radioStr $($d.Nom)" -ForegroundColor $(
                if ($d.Statut -eq 'OK') { 'Green' } elseif ($d.Statut -eq 'Error') { 'Red' } else { 'Yellow' }
            )
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
            if ($null -ne $d.BusNumber -and $d.BusNumber -ne '') { Write-Host "  Bus Number   : $($d.BusNumber)" }   # FIX PSA: $null à gauche
            if ($null -ne $d.BusAddress -and $d.BusAddress -ne '') { Write-Host "  Bus Address  : $($d.BusAddress)" }  # FIX PSA: $null à gauche
            if ($null -ne $d.UINumber  -and $d.UINumber  -ne '') { Write-Host "  UI Number    : $($d.UINumber)" }      # FIX PSA: $null à gauche

            Write-Host ""
            Write-Host "  ── Radio BT ──────────────────────────────────────" -ForegroundColor DarkYellow
            if ($d.BDAddress)   { Write-Host "  BD Address   : $($d.BDAddress)" -ForegroundColor Cyan }
            if ($d.BTSpec) {
                Write-Host "  BT Spec      : $($d.BTSpec)" -ForegroundColor Cyan
                Write-Host "  Frequence    : $($d.BTFreq)"
            }
            if ($null -ne $d.LmpVersion) { Write-Host "  LMP Version  : $($d.LmpVersion)" }   # FIX PSA: $null à gauche
            if ($null -ne $d.LmpSubVer)  { Write-Host "  LMP SubVer   : $(\"0x{0:X4}\" -f [int]$d.LmpSubVer)" }   # FIX PSA: $null à gauche
            if ($d.BTVersion)   { Write-Host "  Radio Ver    : $($d.BTVersion)" }
            if ($d.BTManuf)     { Write-Host "  BT Manuf     : $($d.BTManuf)" }

            Write-Host ""
            Write-Host "  ── Driver ────────────────────────────────────────" -ForegroundColor DarkYellow
            if ($d.DriverVer)  { Write-Host "  Version      : $($d.DriverVer)" }
            if ($d.DriverDate) { Write-Host "  Date         : $($d.DriverDate)" }
            if ($d.InfPath)    { Write-Host "  INF          : $($d.InfPath)" }
            if ($d.InfSection) { Write-Host "  INF Section  : $($d.InfSection)" }
            if ($d.Service) {
                Write-Host "  Service      : $($d.Service)"
                $svc = Get-Service -Name $d.Service -ErrorAction SilentlyContinue
                $svcWmi = Get-WmiObject Win32_SystemDriver -Filter "Name='$($d.Service)'" -ErrorAction SilentlyContinue
                if ($svc) {
                    $svcStatusColor = if ($svc.Status -eq 'Running') { 'Green' } elseif ($svc.Status -eq 'Stopped') { 'Red' } else { 'Yellow' }
                    Write-Host "  Svc Status   : $($svc.Status)" -ForegroundColor $svcStatusColor
                    Write-Host "  Svc Start    : $($svc.StartType)"
                    if ($svc.DisplayName -and $svc.DisplayName -ne $d.Service) { Write-Host "  Svc Name     : $($svc.DisplayName)" }
                }
                if ($svcWmi -and $svcWmi.PathName) { Write-Host "  SYS Path     : $($svcWmi.PathName)" }
                else {
                    $sysItem = Get-Item "$env:SystemRoot\System32\drivers\$($d.Service).sys" -ErrorAction SilentlyContinue
                    $sysFile = if ($sysItem) { $sysItem.FullName } else { $null }
                    if ($sysFile) { Write-Host "  SYS          : $sysFile" }
                }
            }

            Write-Host ""
        }

        if (-not $id) {
        Write-Host "  $('─' * 60)" -ForegroundColor DarkGray
        Write-Host "  PERIPHERIQUES PAIRIES / PROFILS BT (WMI)" -ForegroundColor DarkGray
        Write-Host "  $('─' * 60)" -ForegroundColor DarkGray
        $extras = Get-PnpDevice -ErrorAction SilentlyContinue |
                  Where-Object { $_.InstanceId -like 'BTHENUM\*' -or $_.InstanceId -like 'BTH\*' -or $_.InstanceId -like 'BTHLE\*' }
        if ($extras) {
            foreach ($e in $extras) {
                $color2 = if ($e.Status -eq 'OK') { 'Green' } elseif ($e.Status -eq 'Error') { 'Red' } else { 'Yellow' }
                Write-Host ""
                Write-Host "  Caption  : $($e.FriendlyName)"
                Write-Host "  DeviceID : $($e.InstanceId)"
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
        Write-Host "hciconfig -i -id 'BTHENUMxxxxxxxxx' -all *> monster.txt     #Export."
        Write-Host ""
    }
    
# ══════════════════════════════════════════════════════════════════════
#  MAN
# ══════════════════════════════════════════════════════════════════════
$doMan = {
    $txt = "NAME`n" +
"    hciconfig`n" +
"`n" +
"SYNOPSIS`n" +
"    Equivalent Windows de la commande Linux hciconfig.`n" +
"    Liste, inspecte, active et desactive les interfaces Bluetooth.`n" +
"`n" +
"SYNTAX`n" +
"    hciconfig`n" +
"    hciconfig -l  | -list`n" +
"    hciconfig -i  | -info`n" +
"    hciconfig -i  -id <InstanceId>`n" +
"    hciconfig -i  -all`n" +
"    hciconfig -i  -id <InstanceId> -all`n" +
"    hciconfig -up   -id <InstanceId>`n" +
"    hciconfig -down -id <InstanceId>`n" +
"    hciconfig -h  | -help`n" +
"    hciconfig -m  | -man`n" +
"`n" +
"DESCRIPTION`n" +
"    Fusionne les donnees du chip physique (USB/PCI) et du noeud radio`n" +
"    virtuel (SWD\RADIO\) pour afficher une vue complete de chaque`n" +
"    adaptateur Bluetooth : identite, etat UP/DOWN, BD Address, version`n" +
"    BT, driver. Necessite des droits administrateur pour -up et -down.`n" +
"`n" +
"PARAMETRES`n" +
"    -l | -list`n" +
"        Vue courte : nom, statut radio UP/DOWN, BD Address, InstanceId.`n" +
"`n" +
"    -i | -info`n" +
"        Vue info basique de tous les adaptateurs :`n" +
"        Identite    : Nom, Description, Fabricant, Bus, Enumerateur, Classe`n" +
"        Etat        : Radio UP/DOWN, Statut PnP + WMI`n" +
"        Identifiants: InstanceId, InstanceSWD, HardwareIds, Location`n" +
"        Radio BT    : BD Address, BT Version, BT Manufacturer`n" +
"        Driver      : Version, Date`n" +
"        + liste des peripheriques/profils pairies (WMI)`n" +
"`n" +
"    -i -id <InstanceId>`n" +
"        Meme vue basique mais filtre sur un seul adaptateur.`n" +
"        Section peripheriques pairies masquee.`n" +
"`n" +
"    -i -all`n" +
"        Vue info complete de tous les adaptateurs.`n" +
"        Ajoute : features, class GUID, infos registre.`n" +
"`n" +
"    -i -id <InstanceId> -all`n" +
"        Vue info complete d'un seul adaptateur.`n" +
"`n" +
"    -up -id <InstanceId>`n" +
"        Active l'adaptateur. Equivalent hciconfig hci0 up. Requiert admin.`n" +
"`n" +
"    -down -id <InstanceId>`n" +
"        Desactive l'adaptateur. Equivalent hciconfig hci0 down. Requiert admin.`n" +
"`n" +
"    -id <InstanceId>`n" +
"        InstanceId entre guillemets. Recuperable via hciconfig -l.`n" +
"        Exemple : `"USB\VID_8087&PID_0029\8&2EFE0359&0&4`"`n" +
"`n" +
"    -h | -help    Aide courte.`n" +
"    -m | -man     Ce manuel.`n" +
"`n" +
"EQUIVALENCES Linux -> Windows`n" +
"    hciconfig              ->  hciconfig`n" +
"    hciconfig hci0         ->  hciconfig -i -id `"<InstanceId>`"`n" +
"    hciconfig -a           ->  hciconfig -i -all`n" +
"    hciconfig -a hci0      ->  hciconfig -i -id `"<InstanceId>`" -all`n" +
"    hciconfig hci0 up      ->  hciconfig -up   -id `"<InstanceId>`"`n" +
"    hciconfig hci0 down    ->  hciconfig -down -id `"<InstanceId>`"`n" +
"`n" +
"NOTES`n" +
"    - Windows 10 / Windows 11, PowerShell 5.1+`n" +
"    - -up / -down necessitent une session administrateur`n" +
"    - Le & dans l'InstanceId doit etre entre guillemets`n" +
"`n" +
"SEE ALSO`n" +
"    Get-PnpDevice, Get-PnpDeviceProperty`n" +
"    Enable-PnpDevice, Disable-PnpDevice`n" +
"    Get-WmiObject Win32_PnPEntity`n" +
"    https://linux.die.net/man/8/hciconfig`n"

    Write-Host $txt -ForegroundColor Gray
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
            $filtered = $devicesToShow | Where-Object { $_.InstanceId -like "*$id*" }
            if ($filtered) {
                $devicesToShow = $filtered
                & $doInfo
            } else {
                $periph = Get-PnpDevice -ErrorAction SilentlyContinue |
                          Where-Object { $_.InstanceId -like "*$id*" -and (
                              $_.InstanceId -like 'BTHENUM\*' -or
                              $_.InstanceId -like 'BTH\*' -or
                              $_.InstanceId -like 'BTHLE\*') }
                if (-not $periph) { Write-Host "`n  Aucun peripherique trouve pour l'ID : $id`n" -ForegroundColor Red; return }
                $sep = '─' * 60
                foreach ($e in $periph) {
                    $color2 = if ($e.Status -eq 'OK') { 'Green' } elseif ($e.Status -eq 'Error') { 'Red' } else { 'Yellow' }
                    $eProps = Get-PnpDeviceProperty -InstanceId $e.InstanceId -ErrorAction SilentlyContinue
                    $eMfg   = ($eProps | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_Manufacturer'  }).Data
                    $eDesc  = ($eProps | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_DeviceDesc'    }).Data
                    $eHwIds = ($eProps | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_HardwareIds'   }).Data
                    $eDrv   = ($eProps | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_DriverVersion' }).Data
                    $eDrvDt = ($eProps | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_DriverDate'    }).Data
                    Write-Host ""
                    Write-Host "  $sep" -ForegroundColor DarkCyan
                    Write-Host "  PERIPHERIQUE : $($e.FriendlyName)" -ForegroundColor Cyan
                    Write-Host "  $sep" -ForegroundColor DarkCyan
                    Write-Host ""
                    Write-Host "  ── Identite ─────────────────────────────────────────" -ForegroundColor DarkYellow
                    Write-Host "  Nom          : $($e.FriendlyName)"
                    if ($eDesc) { Write-Host "  Description  : $eDesc" }
                    if ($eMfg)  { Write-Host "  Fabricant    : $eMfg" }
                    Write-Host ""
                    Write-Host "  ── Etat ──────────────────────────────────────────────" -ForegroundColor DarkYellow
                    Write-Host "  Statut PnP   : $($e.Status)" -ForegroundColor $color2
                    Write-Host ""
                    Write-Host "  ── Identifiants ──────────────────────────────────────" -ForegroundColor DarkYellow
                    Write-Host "  InstanceId   : $($e.InstanceId)"
                    if ($eHwIds) { Write-Host "  HardwareIds  : $(($eHwIds -join ', '))" }
                    if ($eDrv) {
                        Write-Host ""
                        Write-Host "  ── Driver ────────────────────────────────────────────" -ForegroundColor DarkYellow
                        Write-Host "  Version      : $eDrv"
                        if ($eDrvDt) { Write-Host "  Date         : $(([datetime]$eDrvDt).ToString('yyyy-MM-dd'))" }
                    }

                    if ($a -or $all) {
                        Write-Host ""
                        Write-Host "  ── Proprietes etendues (-all) ────────────────────────" -ForegroundColor DarkMagenta
                        foreach ($prop in ($eProps | Sort-Object KeyName)) {
                            $val = if ($prop.Data -is [array]) { $prop.Data -join ', ' } else { $prop.Data }
                            if ($null -ne $val -and "$val" -ne '') {
                                Write-Host ("  {0,-42} : {1}" -f $prop.KeyName, $val) -ForegroundColor DarkGray
                            }
                        }
                    }

                    Write-Host ""
                }
            }
        } else {
            & $doInfo
        }
        return
    }

    if ($a -or $all) {
        $devicesToShow = & $getData
        & $doList
        & $doInfo
        return
    }

    $devicesToShow = & $getData
    & $doList
    & $doInfo
}
Export-ModuleMember -Function hciconfig

# ══════════════════════════════════════════════════════════════════════════════
#  iwconfig — Equivalent Windows de la commande Linux iwconfig / iw
# ══════════════════════════════════════════════════════════════════════════════
function iwconfig {
<#
.SYNOPSIS
    Equivalent Windows de la commande Linux iwconfig / iw.
.EXAMPLE
    iwconfig                       # tous les adaptateurs Wi-Fi, vue complete
    iwconfig -l | -list            # liste courte
    iwconfig -i | -info            # infos detaillees
    iwconfig -a | -all             # tout (defaut)
    iwconfig -up   -id "Wi-Fi"    # activer
    iwconfig -down -id "Wi-Fi"    # desactiver
    iwconfig -h | -help
    iwconfig -m | -man
    iwconfig -i -id "Wi-Fi" -all *> wifi.txt    # Export
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
    #  HELPERS : parsing netsh
    # ══════════════════════════════════════════════════════════════════════
    function Get-NetshWlanInterfaces {
        $raw = netsh wlan show interfaces 2>$null
        if (-not $raw) { return @() }
        $blocks  = @()
        $current = $null
        foreach ($line in $raw) {
            if ($line -match '^\s+Name\s+:\s+(.+)$') {
                if ($current) { $blocks += $current }
                $current = @{ Name = $Matches[1].Trim() }
            } elseif ($current -and $line -match '^\s+(.+?)\s+:\s+(.*)$') {
                $key = $Matches[1].Trim() -replace '\s+','_'
                $val = $Matches[2].Trim()
                $current[$key] = $val
            }
        }
        if ($current) { $blocks += $current }
        return $blocks
    }

    function Get-NetshWlanProfiles {
        $raw = netsh wlan show profiles 2>$null
        $profiles = @()
        foreach ($line in $raw) {
            if ($line -match 'All User Profile\s*:\s*(.+)$' -or $line -match 'Profil_tous_util\w+\s*:\s*(.+)$') {
                $profiles += $Matches[1].Trim()
            }
        }
        return $profiles
    }

    # ══════════════════════════════════════════════════════════════════════
    #  COLLECTE ET CROISEMENT DES DONNEES
    # ══════════════════════════════════════════════════════════════════════
    $getData = {
        # Adaptateurs reseau Wi-Fi via WMI (PS 5.1 safe)
        $wmiNets = Get-WmiObject -Class Win32_NetworkAdapter -ErrorAction SilentlyContinue |
                   Where-Object { $_.AdapterType -like '*Ethernet 802.11*' -or $_.Name -like '*Wi-Fi*' -or $_.Name -like '*Wireless*' -or $_.Name -like '*802.11*' }

        # PnP : classe Net, filtre Wi-Fi/Wireless
        $pnpAll = Get-PnpDevice -Class Net -ErrorAction SilentlyContinue |
                  Where-Object { $_.FriendlyName -like '*Wi-Fi*' -or $_.FriendlyName -like '*Wireless*' -or $_.FriendlyName -like '*802.11*' -or $_.FriendlyName -like '*WLAN*' }

        # netsh : interfaces actives avec SSID, signal, etc.
        $netshAll = Get-NetshWlanInterfaces

        # Profils sauvegardes
        $profileList = Get-NetshWlanProfiles

        $result = foreach ($p in $pnpAll) {

            $props = Get-PnpDeviceProperty -InstanceId $p.InstanceId -ErrorAction SilentlyContinue
            $driver      = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_DriverVersion'         }).Data
            $driverDate  = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_DriverDate'            }).Data
            $mfg         = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_Manufacturer'          }).Data
            $desc        = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_DeviceDesc'            }).Data
            $busType     = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_BusReportedDeviceDesc' }).Data
            $locInfo     = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_LocationInfo'          }).Data
            $enumerator  = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_EnumeratorName'        }).Data
            $class       = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_Class'                 }).Data
            $hwIds       = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_HardwareIds'           }).Data
            $infPath     = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_DriverInfPath'         }).Data
            $infSection  = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_DriverInfSection'      }).Data
            $service     = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_Service'               }).Data
            $busNum      = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_BusNumber'             }).Data
            $busAddr     = ($props | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_Address'               }).Data

            # Croisement WMI -> MAC physique
            $wmi = $wmiNets | Where-Object { $_.PNPDeviceID -eq $p.InstanceId } | Select-Object -First 1
            $macAddr = if ($wmi -and $wmi.MACAddress) { $wmi.MACAddress } else { $null }
            $netName = if ($wmi -and $wmi.NetConnectionID) { $wmi.NetConnectionID } else { $p.FriendlyName }

            # Croisement netsh -> donnees radio live
            $ns = $netshAll | Where-Object { $_['Name'] -eq $netName } | Select-Object -First 1
            if (-not $ns) {
                $ns = $netshAll | Where-Object { $_['Name'] -like "*$($p.FriendlyName)*" } | Select-Object -First 1
            }

            $ssid        = if ($ns) { $ns['SSID'] }                     else { $null }
            $bssid       = if ($ns) { $ns['BSSID'] }                    else { $null }
            $radioType   = if ($ns) { $ns['Radio_type'] }               else { $null }
            $auth        = if ($ns) { $ns['Authentication'] }           else { $null }
            $cipher      = if ($ns) { $ns['Cipher'] }                   else { $null }
            $channel     = if ($ns) { $ns['Channel'] }                  else { $null }
            $receiveRate = if ($ns) { $ns['Receive_rate_(Mbps)'] }      else { $null }
            $transmitRate= if ($ns) { $ns['Transmit_rate_(Mbps)'] }     else { $null }
            $signalPct   = if ($ns) { $ns['Signal'] }                   else { $null }
            $state       = if ($ns) { $ns['State'] }                    else { $null }
            $hostedNet   = if ($ns) { $ns['Hosted_network_status'] }    else { $null }

            # Deduction bande depuis channel
            $band = $null
            if ($null -ne $channel -and $channel -ne '') {
                $chInt = [int]($channel -replace '[^0-9]','')
                if     ($chInt -ge 1   -and $chInt -le 14)  { $band = '2.4 GHz' }
                elseif ($chInt -ge 36  -and $chInt -le 177) { $band = '5 GHz'   }
                elseif ($chInt -ge 1   -and $chInt -le 233 -and $radioType -like '*6*') { $band = '6 GHz' }
            }

            # RadioUp depuis netsh State ou PnP Status
            $radioUp = $null
            if ($state) {
                $radioUp = if ($state -like '*connected*' -or $state -like '*connecte*') { 'UP' } else { 'DOWN' }
            } elseif ($p.Status -eq 'OK') {
                $radioUp = 'UP'
            } else {
                $radioUp = 'DOWN'
            }

            [PSCustomObject]@{
                # Identite
                Nom          = $p.FriendlyName
                NetName      = $netName
                Description  = if ($desc)    { $desc }  else { $null }
                Fabricant    = if ($mfg)     { $mfg }   else { $null }
                BusDesc      = $busType
                Enumerateur  = $enumerator
                Classe       = if ($class)   { $class } else { $p.Class }
                # Etat
                Statut       = $p.Status
                RadioUp      = $radioUp
                State        = $state
                # Identifiants
                InstanceId   = $p.InstanceId
                HardwareIds  = if ($hwIds)   { ($hwIds -join ', ') } else { '' }
                Location     = $locInfo
                BusNumber    = $busNum
                BusAddress   = $busAddr
                # Radio Wi-Fi
                MACAddress   = $macAddr
                SSID         = $ssid
                BSSID        = $bssid
                RadioType    = $radioType
                Band         = $band
                Channel      = $channel
                Signal       = $signalPct
                TxRate       = $transmitRate
                RxRate       = $receiveRate
                Auth         = $auth
                Cipher       = $cipher
                HostedNet    = $hostedNet
                Profiles     = $profileList
                # Driver
                DriverVer    = $driver
                DriverDate   = if ($driverDate) { ([datetime]$driverDate).ToString('yyyy-MM-dd') } else { '' }
                InfPath      = $infPath
                InfSection   = $infSection
                Service      = $service
                # Raw props pour -all
                _RawProps     = $props
            }
        }
        $result
    }

    # ══════════════════════════════════════════════════════════════════════
    #  AFFICHAGE COURT  (-l / -list)
    # ══════════════════════════════════════════════════════════════════════
    $doList = {
        $devices = $devicesToShow
        if (-not $devices) { Write-Host "`n  Aucun adaptateur Wi-Fi trouve." -ForegroundColor Red; return }
        Write-Host ""
        foreach ($d in $devices) {
            $color    = if ($d.Statut -eq 'OK') { 'Green' } elseif ($d.Statut -eq 'Error') { 'Red' } else { 'Yellow' }
            $radioStr = if ($d.RadioUp) { " [$($d.RadioUp)]" } else { '' }
            Write-Host "  [$($d.Statut)]$radioStr $($d.Nom)" -ForegroundColor $color
            if ($d.MACAddress) { Write-Host "       MAC  : $($d.MACAddress)"  -ForegroundColor Cyan }
            if ($d.SSID)       { Write-Host "       SSID : $($d.SSID)"        -ForegroundColor Cyan }
            Write-Host "       ID  : $($d.InstanceId)" -ForegroundColor DarkGray
            Write-Host ""
        }
    }

    # ══════════════════════════════════════════════════════════════════════
    #  AFFICHAGE DETAIL  (-i / -info)
    # ══════════════════════════════════════════════════════════════════════
    $doInfo = {
        $devices = $devicesToShow
        if (-not $devices) { Write-Host "`n  Aucun adaptateur Wi-Fi trouve." -ForegroundColor Red; return }

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
            if ($d.NetName -and $d.NetName -ne $d.Nom) { Write-Host "  Interface    : $($d.NetName)" }
            if ($d.Description) { Write-Host "  Description  : $($d.Description)" }
            if ($d.Fabricant)   { Write-Host "  Fabricant    : $($d.Fabricant)" }
            if ($d.BusDesc)     { Write-Host "  Bus          : $($d.BusDesc)" }
            if ($d.Enumerateur) { Write-Host "  Enumerateur  : $($d.Enumerateur)" }
            if ($d.Classe)      { Write-Host "  Classe       : $($d.Classe)" }

            Write-Host ""
            Write-Host "  ── Etat ──────────────────────────────────────────" -ForegroundColor DarkYellow
            $radioColor = if ($d.RadioUp -eq 'UP') { 'Green' } else { 'Red' }
            if ($d.RadioUp) { Write-Host "  Radio        : $($d.RadioUp)" -ForegroundColor $radioColor }
            Write-Host "  Statut PnP   : $($d.Statut)" -ForegroundColor $color
            if ($d.State)   { Write-Host "  Etat netsh   : $($d.State)" }

            Write-Host ""
            Write-Host "  ── Identifiants ──────────────────────────────────" -ForegroundColor DarkYellow
            Write-Host "  InstanceId   : $($d.InstanceId)"
            if ($d.HardwareIds) { Write-Host "  HardwareIds  : $($d.HardwareIds)" }
            if ($d.Location)    { Write-Host "  Location     : $($d.Location)" }
            if ($null -ne $d.BusNumber  -and $d.BusNumber  -ne '') { Write-Host "  Bus Number   : $($d.BusNumber)" }
            if ($null -ne $d.BusAddress -and $d.BusAddress -ne '') { Write-Host "  Bus Address  : $($d.BusAddress)" }

            Write-Host ""
            Write-Host "  ── Radio Wi-Fi ───────────────────────────────────" -ForegroundColor DarkYellow
            if ($d.MACAddress) { Write-Host "  MAC Address  : $($d.MACAddress)" -ForegroundColor Cyan }
            if ($d.SSID)       { Write-Host "  SSID         : $($d.SSID)"       -ForegroundColor Cyan }
            if ($d.BSSID)      { Write-Host "  BSSID        : $($d.BSSID)" }
            if ($d.RadioType)  { Write-Host "  Standard     : $($d.RadioType)" }
            if ($d.Band)       { Write-Host "  Bande        : $($d.Band)" }
            if ($d.Channel)    { Write-Host "  Canal        : $($d.Channel)" }
            if ($d.Signal)     { Write-Host "  Signal       : $($d.Signal)" }
            if ($d.TxRate)     { Write-Host "  Tx Rate      : $($d.TxRate) Mbps" }
            if ($d.RxRate)     { Write-Host "  Rx Rate      : $($d.RxRate) Mbps" }
            if ($d.Auth)       { Write-Host "  Auth         : $($d.Auth)" }
            if ($d.Cipher)     { Write-Host "  Cipher       : $($d.Cipher)" }
            if ($d.HostedNet)  { Write-Host "  Hosted Net   : $($d.HostedNet)" }

            if ($d.Profiles -and $d.Profiles.Count -gt 0) {
                Write-Host ""
                Write-Host "  ── Profils sauvegardes ───────────────────────────" -ForegroundColor DarkYellow
                foreach ($prof in $d.Profiles) {
                    Write-Host "    - $prof"
                }
            }

            Write-Host ""
            Write-Host "  ── Driver ────────────────────────────────────────" -ForegroundColor DarkYellow
            if ($d.DriverVer)  { Write-Host "  Version      : $($d.DriverVer)" }
            if ($d.DriverDate) { Write-Host "  Date         : $($d.DriverDate)" }
            if ($d.InfPath)    { Write-Host "  INF          : $($d.InfPath)" }
            if ($d.InfSection) { Write-Host "  INF Section  : $($d.InfSection)" }
            if ($d.Service) {
                Write-Host "  Service      : $($d.Service)"
                $svc    = Get-Service -Name $d.Service -ErrorAction SilentlyContinue
                $svcWmi = Get-WmiObject Win32_SystemDriver -Filter "Name='$($d.Service)'" -ErrorAction SilentlyContinue
                if ($svc) {
                    $svcColor = if ($svc.Status -eq 'Running') { 'Green' } elseif ($svc.Status -eq 'Stopped') { 'Red' } else { 'Yellow' }
                    Write-Host "  Svc Status   : $($svc.Status)" -ForegroundColor $svcColor
                    Write-Host "  Svc Start    : $($svc.StartType)"
                    if ($svc.DisplayName -and $svc.DisplayName -ne $d.Service) { Write-Host "  Svc Name     : $($svc.DisplayName)" }
                }
                if ($svcWmi -and $svcWmi.PathName) { Write-Host "  SYS Path     : $($svcWmi.PathName)" }
                else {
                    $sysItem = Get-Item "$env:SystemRoot\System32\drivers\$($d.Service).sys" -ErrorAction SilentlyContinue
                    if ($sysItem) { Write-Host "  SYS          : $($sysItem.FullName)" }
                }
            }

            if ($a -or $all) {
                Write-Host ""
                Write-Host "  ── Proprietes etendues (-all) ────────────────────" -ForegroundColor DarkMagenta
                foreach ($prop in ($d._RawProps | Sort-Object KeyName)) {
                    $val = if ($prop.Data -is [array]) { $prop.Data -join ', ' } else { $prop.Data }
                    if ($null -ne $val -and "$val" -ne '') {
                        Write-Host ("  {0,-42} : {1}" -f $prop.KeyName, $val) -ForegroundColor DarkGray
                    }
                }
            }

            Write-Host ""
        }
    }

    # ══════════════════════════════════════════════════════════════════════
    #  HELP
    # ══════════════════════════════════════════════════════════════════════
    $doHelp = {
        Write-Host ""
        Write-Host "  iwconfig — Equivalent Windows de iwconfig / iw Linux" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Usage:" -ForegroundColor Yellow
        Write-Host "    iwconfig                             Defaut : liste + info basique tous"
        Write-Host "    iwconfig -l  | -list                 Liste courte (nom + statut + MAC + SSID)"
        Write-Host "    iwconfig -i  | -info                 Info basique tous les adaptateurs"
        Write-Host "    iwconfig -i  -id `"<Nom>`"             Info basique un seul adaptateur exemple NOM:Intel(R) Wi-Fi 6 AX200 160MHz"
        Write-Host "    iwconfig -i  -all                    Info complete tous les adaptateurs"
        Write-Host "    iwconfig -i  -id `"<Nom>`" -all        Info complete un seul adaptateur"
        Write-Host "    iwconfig -up   -id `"<Nom>`"           Active un adaptateur"
        Write-Host "    iwconfig -down -id `"<Nom>`"           Desactive un adaptateur"
        Write-Host "    iwconfig -h  | -help                 Cette aide"
        Write-Host "    iwconfig -m  | -man                  Manuel complet"
        Write-Host ""
        Write-Host "  /!\ -id prend le nom de l'interface reseau (ex: 'Wi-Fi', 'Wi-Fi 2') :" -ForegroundColor Yellow
        Write-Host '      iwconfig -i -id "Wi-Fi"'
        Write-Host ""
        Write-Host "  iwconfig -i -id 'Wi-Fi' -all *> wifi.txt     # Export"
        Write-Host ""
    }

    # ══════════════════════════════════════════════════════════════════════
    #  MAN
    # ══════════════════════════════════════════════════════════════════════
    $doMan = {
        $txt = "NAME`n" +
"    iwconfig`n" +
"`n" +
"SYNOPSIS`n" +
"    Equivalent Windows de la commande Linux iwconfig / iw.`n" +
"    Liste, inspecte, active et desactive les interfaces Wi-Fi.`n" +
"`n" +
"SYNTAX`n" +
"    iwconfig`n" +
"    iwconfig -l  | -list`n" +
"    iwconfig -i  | -info`n" +
"    iwconfig -i  -id <Nom>`n" +
"    iwconfig -i  -all`n" +
"    iwconfig -i  -id <Nom> -all    #exemple NOM:Intel(R) Wi-Fi 6 AX200 160MHz`n" +
"    iwconfig -up   -id <Nom>`n" +
"    iwconfig -down -id <Nom>`n" +
"    iwconfig -h  | -help`n" +
"    iwconfig -m  | -man`n" +
"`n" +
"DESCRIPTION`n" +
"    Fusionne les donnees PnP, WMI (Win32_NetworkAdapter) et netsh wlan`n" +
"    pour afficher une vue complete de chaque adaptateur Wi-Fi :`n" +
"    identite, etat UP/DOWN, MAC Address, SSID, BSSID, standard 802.11,`n" +
"    bande, canal, signal, debit Tx/Rx, auth, cipher, driver.`n" +
"    Necessite des droits administrateur pour -up et -down.`n" +
"`n" +
"PARAMETRES`n" +
"    -l | -list`n" +
"        Vue courte : nom, statut radio UP/DOWN, MAC Address, SSID, InstanceId.`n" +
"`n" +
"    -i | -info`n" +
"        Vue info basique de tous les adaptateurs :`n" +
"        Identite    : Nom, Interface, Description, Fabricant, Bus, Enumerateur`n" +
"        Etat        : Radio UP/DOWN, Statut PnP, Etat netsh`n" +
"        Identifiants: InstanceId, HardwareIds, Location`n" +
"        Radio Wi-Fi : MAC, SSID, BSSID, Standard, Bande, Canal, Signal`n" +
"                      Tx/Rx Rate, Auth, Cipher`n" +
"        Profils     : liste des profils Wi-Fi sauvegardes`n" +
"        Driver      : Version, Date, INF, Service`n" +
"`n" +
"    -i -id <Nom>`n" +
"        Meme vue basique mais filtre sur un seul adaptateur.`n" +
"        <Nom> = nom de l'interface reseau (ex: Wi-Fi, Wi-Fi 2).`n" +
"`n" +
"    -i -all`n" +
"        Vue info complete de tous les adaptateurs.`n" +
"        Ajoute : toutes les proprietes DEVPKEY brutes.`n" +
"`n" +
"    -i -id <Nom> -all`n" +
"        Vue info complete d'un seul adaptateur.`n" +
"`n" +
"    -up -id <Nom>`n" +
"        Active l'adaptateur. Equivalent iw dev wlan0 set type managed + ip link up.`n" +
"        Requiert admin.`n" +
"`n" +
"    -down -id <Nom>`n" +
"        Desactive l'adaptateur. Equivalent ip link down wlan0.`n" +
"        Requiert admin.`n" +
"`n" +
"    -id <Nom>`n" +
"        Nom de l'interface reseau entre guillemets si espaces.`n" +
"        Recuperable via iwconfig -l  (colonne Interface).`n" +
"        Exemples : 'Wi-Fi'  'Wi-Fi 2'  'Wireless Network Connection'`n" +
"`n" +
"    -h | -help    Aide courte.`n" +
"    -m | -man     Ce manuel.`n" +
"`n" +
"EQUIVALENCES Linux -> Windows`n" +
"    iwconfig                   ->  iwconfig`n" +
"    iw dev                     ->  iwconfig -l`n" +
"    iwconfig wlan0             ->  iwconfig -i -id `"Wi-Fi`"`n" +
"    ip link set wlan0 up       ->  iwconfig -up   -id `"Wi-Fi`"`n" +
"    ip link set wlan0 down     ->  iwconfig -down -id `"Wi-Fi`"`n" +
"`n" +
"SOURCES DE DONNEES`n" +
"    - Get-PnpDevice / Get-PnpDeviceProperty  (chip physique)`n" +
"    - Get-WmiObject Win32_NetworkAdapter     (MAC, NetConnectionID)`n" +
"    - netsh wlan show interfaces             (SSID, signal, debit live)`n" +
"    - netsh wlan show profiles               (profils sauvegardes)`n" +
"    - Get-Service / Win32_SystemDriver       (service driver)`n" +
"`n" +
"NOTES`n" +
"    - Windows 10 / Windows 11, PowerShell 5.1+`n" +
"    - -up / -down necessitent une session administrateur`n" +
"    - SSID/Signal/Debit absents si l'adaptateur est deconnecte`n" +
"    - Les profils sont globaux (pas filtres par adaptateur)`n" +
"`n" +
"SEE ALSO`n" +
"    Get-PnpDevice, Get-PnpDeviceProperty`n" +
"    Get-WmiObject Win32_NetworkAdapter`n" +
"    Enable-NetAdapter, Disable-NetAdapter`n" +
"    netsh wlan show interfaces`n" +
"    https://linux.die.net/man/8/iwconfig`n"

        Write-Host $txt -ForegroundColor Gray
    }

    # ══════════════════════════════════════════════════════════════════════
    #  DISPATCH
    # ══════════════════════════════════════════════════════════════════════
    if ($args -contains '--help') { & $doHelp; return }
    if ($args -contains '--man')  { & $doMan;  return }
    if ($h -or $help) { & $doHelp; return }
    if ($m -or $man)  { & $doMan;  return }

    if ($up) {
        if (-not $isAdmin) { Write-Host "`n  [ERREUR] Droits administrateur requis.`n" -ForegroundColor Red; return }
        if (-not $id)      { Write-Host "`n  [ERREUR] -id requis.  Ex: iwconfig -up -id 'Wi-Fi'`n" -ForegroundColor Red; return }
        Write-Host "`n  Activation : $id" -ForegroundColor Cyan
        try {
            Enable-NetAdapter -Name $id -Confirm:$false -ErrorAction Stop
            Write-Host "  [OK] Adaptateur active.`n" -ForegroundColor Green
        } catch { Write-Host "  [ERREUR] $($_.Exception.Message)`n" -ForegroundColor Red }
        return
    }

    if ($down) {
        if (-not $isAdmin) { Write-Host "`n  [ERREUR] Droits administrateur requis.`n" -ForegroundColor Red; return }
        if (-not $id)      { Write-Host "`n  [ERREUR] -id requis.  Ex: iwconfig -down -id 'Wi-Fi'`n" -ForegroundColor Red; return }
        Write-Host "`n  Desactivation : $id" -ForegroundColor Cyan
        try {
            Disable-NetAdapter -Name $id -Confirm:$false -ErrorAction Stop
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
            $filtered = $devicesToShow | Where-Object { $_.NetName -like "*$id*" -or $_.Nom -like "*$id*" }
            if ($filtered) {
                $devicesToShow = $filtered
                & $doInfo
            } else {
                Write-Host "`n  Aucun adaptateur Wi-Fi trouve pour : $id`n" -ForegroundColor Red
            }
        } else {
            & $doInfo
        }
        return
    }

    if ($a -or $all) {
        $devicesToShow = & $getData
        & $doList
        & $doInfo
        return
    }

    $devicesToShow = & $getData
    & $doList
    & $doInfo
}
Export-ModuleMember -Function hciconfig, iwconfig
