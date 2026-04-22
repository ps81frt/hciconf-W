# hciconfig-W

Auteur : ps81frt  
Repo   : https://github.com/ps81frt/hciconf-W  
Fichier: `hciconfig.psm1`  
Requis : PowerShell **7+** — Windows 10/11

> ⚠️ **PS 5.1 (Windows PowerShell) non supporté** : le script utilise l'opérateur null-conditional `?.` introduit en PS 7. Malgré la mention `5.1+` dans le fichier source, le chargement échoue sur PS 5.1.

---

## Description

Fonction PowerShell équivalente à `hciconfig` Linux.  
Liste, inspecte, active et désactive les adaptateurs Bluetooth.  
Croise **4 sources** : PnP (chip physique), SWD\RADIO (nœud radio virtuel), WMI, et l'API native Win32 `bluetoothapis.dll` via P/Invoke.

---

## Installation

```powershell
# 1. ExecutionPolicy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# 2. Téléchargement et extraction
Invoke-WebRequest https://github.com/ps81frt/hciconf-W/archive/refs/heads/main.zip -OutFile "$env:TEMP\hciconf-W.zip"

# 3. Déblocage et extraction
Unblock-File "$env:TEMP\hciconf-W.zip"
Expand-Archive "$env:TEMP\hciconf-W.zip" -DestinationPath "$env:TEMP\hciconf-W"
Remove-Item "$env:TEMP\hciconf-W.zip"

$srcDir = "$env:TEMP\hciconf-W\hciconf-W-main"
$srcPsd = "$srcDir\hciconfig.psd1"

# 4. Création des dossiers
$dest51 = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\hciconfig51"
$dest7  = "$env:USERPROFILE\Documents\PowerShell\Modules\hciconfig7"
New-Item -ItemType Directory -Force -Path $dest51 | Out-Null
New-Item -ItemType Directory -Force -Path $dest7  | Out-Null

# 5. Installation pour PowerShell 5.1 (avec hciconfig5.psm1)
$src51 = "$srcDir\hciconfig5.psm1"
if (Test-Path $src51) {
    $target51 = "$dest51\hciconfig5.psm1"
    if (Test-Path $target51) {
        $rep = Read-Host "  [!] Deja installe dans $dest51`n      Ecraser ? (o/N)"
        if ($rep -match '^[oO]$') {
            Copy-Item $src51 $target51 -Force
            Unblock-File $target51
            if (Test-Path $srcPsd) { Copy-Item $srcPsd "$dest51\hciconfig.psd1" -Force }
            Write-Host "  [OK] Installe pour PS5.1 : $dest51" -ForegroundColor Green
        }
    } else {
        Copy-Item $src51 $target51 -Force
        Unblock-File $target51
        if (Test-Path $srcPsd) { Copy-Item $srcPsd "$dest51\hciconfig.psd1" -Force }
        Write-Host "  [OK] Installe pour PS5.1 : $dest51" -ForegroundColor Green
    }
}

# 6. Installation pour PowerShell 7 (avec hciconfig.psm1 original)
$src7 = "$srcDir\hciconfig.psm1"
if (Test-Path $src7) {
    $target7 = "$dest7\hciconfig.psm1"
    if (Test-Path $target7) {
        $rep = Read-Host "  [!] Deja installe dans $dest7`n      Ecraser ? (o/N)"
        if ($rep -match '^[oO]$') {
            Copy-Item $src7 $target7 -Force
            Unblock-File $target7
            if (Test-Path $srcPsd) { Copy-Item $srcPsd "$dest7\hciconfig.psd1" -Force }
            Write-Host "  [OK] Installe pour PS7 : $dest7" -ForegroundColor Green
        }
    } else {
        Copy-Item $src7 $target7 -Force
        Unblock-File $target7
        if (Test-Path $srcPsd) { Copy-Item $srcPsd "$dest7\hciconfig.psd1" -Force }
        Write-Host "  [OK] Installe pour PS7 : $dest7" -ForegroundColor Green
    }
}

# 7. Nettoyage
Remove-Item "$env:TEMP\hciconf-W" -Recurse

Write-Host "`n  [OK] Installation terminee !" -ForegroundColor Green
Write-Host "  Pour PS5.1 : powershell -Version 5.1" -ForegroundColor Cyan
Write-Host "  Pour PS7    : pwsh" -ForegroundColor Cyan
```

Pour vérifier :

```powershell
Get-Module -ListAvailable hciconfig
```

---

## Syntaxe

```
hciconfig                                          # défaut : liste courte + détail tous
hciconfig -l  | -list                              # liste courte
hciconfig -i  | -info                              # détail tous les adaptateurs
hciconfig -i  -id "<InstanceId>"                   # détail un seul adaptateur
hciconfig -i  -all                                 # détail complet tous (propriétés étendues)
hciconfig -i  -id "<InstanceId>" -all              # détail complet un seul
hciconfig -up   -id "<InstanceId>"                 # activer  [admin requis]
hciconfig -down -id "<InstanceId>"                 # désactiver  [admin requis]
hciconfig -h  | -help                              # aide courte
hciconfig -m  | -man                               # manuel complet

# Export vers fichier
hciconfig -i -id "BTHENUMxxxxxxxxx" -all *> monster.txt
```

> L'InstanceId contient des `&` et `\` — **toujours le quoter**.

---

## Paramètres

| Paramètre | Type | Description |
|-----------|------|-------------|
| `-l` / `-list` | switch | Liste courte |
| `-i` / `-info` | switch | Vue détaillée |
| `-a` / `-all` | switch | Propriétés étendues (tous les DEVPKEY disponibles) |
| `-up` | switch | Active l'adaptateur ciblé par `-id` |
| `-down` | switch | Désactive l'adaptateur ciblé par `-id` |
| `-id` | string | InstanceId de l'adaptateur ou périphérique cible |
| `-h` / `-help` | switch | Aide courte |
| `-m` / `-man` | switch | Manuel complet |

---

## Équivalences Linux → Windows

| Linux | Windows |
|-------|---------|
| `hciconfig` | `hciconfig` |
| `hciconfig hci0` | `hciconfig -i -id "<InstanceId>"` |
| `hciconfig -a` | `hciconfig -i -all` |
| `hciconfig -a hci0` | `hciconfig -i -id "<InstanceId>" -all` |
| `hciconfig hci0 up` | `hciconfig -up -id "<InstanceId>"` |
| `hciconfig hci0 down` | `hciconfig -down -id "<InstanceId>"` |

---

## Architecture interne

### Blocs

| Bloc | Type | Rôle |
|------|------|------|
| `$getData` | scriptblock | Collecte et fusion de toutes les sources |
| `Get-BtRadioInfoNative` | fonction interne | P/Invoke `bluetoothapis.dll` |
| `$doList` | scriptblock | Affichage court |
| `$doInfo` | scriptblock | Affichage détaillé par sections |
| `$doHelp` | scriptblock | Aide courte |
| `$doMan` | scriptblock | Manuel complet (here-string) |

---

## Bloc `$getData` — détail

### Étape 0 — Type .NET P/Invoke (Add-Type)

Déclaré une seule fois par session via `Add-Type -Namespace HciConfig -Name BtRadioNative`.  
Si le type existe déjà (`PSTypeName` check), le bloc `Add-Type` est ignoré silencieusement.

Structures déclarées (SDK `bthdef.h`) :

| Struct | Champs utiles |
|--------|---------------|
| `BLUETOOTH_FIND_RADIO_PARAMS` | `dwSize` |
| `BLUETOOTH_RADIO_INFO` | `address[6]` (BD_ADDR LSB-first), `szName`, `ulClassofDevice`, `lmpSubversion`, `manufacturer` |

Fonctions importées depuis `bluetoothapis.dll` :

| Fonction | Usage |
|----------|-------|
| `BluetoothFindFirstRadio` | Premier handle radio |
| `BluetoothFindNextRadio` | Handle radio suivant |
| `BluetoothFindRadioClose` | Fermeture du handle de recherche |
| `BluetoothGetRadioInfo` | Remplit `BLUETOOTH_RADIO_INFO` |
| `CloseHandle` (kernel32) | Fermeture de chaque handle radio |

### Fonction interne `Get-BtRadioInfoNative`

Énumère tous les handles radio via `BluetoothFindFirstRadio` / `BluetoothFindNextRadio`.  
Pour chaque radio : appelle `BluetoothGetRadioInfo`, inverse les 6 bytes BD_ADDR (LSB→MSB), formate en `XX:XX:XX:XX:XX:XX`.  
Retourne une liste de `PSCustomObject` avec `BDAddr`, `LmpSubversion`, `Manufacturer`.  
Ferme proprement chaque handle. Retourne `@()` si P/Invoke non disponible.

### Étapes de collecte

| Variable | Cmdlet | Filtre |
|----------|--------|--------|
| `$nativeRadios` | `Get-BtRadioInfoNative` | Tous les handles radio natifs |
| `$pnpAll` | `Get-PnpDevice -Class Bluetooth` | Exclut `BTHENUM\*`, `BTH\*`, `BTHLE\*` |
| `$swdAll` | `Get-PnpDevice` | `InstanceId -like 'SWD\RADIO\BLUETOOTH*'` |
| `$wmiAll` | `Get-WmiObject Win32_PnPEntity` | `Caption LIKE '%Bluetooth%'` |

### Propriétés lues via `Get-PnpDeviceProperty`

**Sur le chip PnP (`$pnpAll`) :**

| Variable | DEVPKEY |
|----------|---------|
| `$driver` | `DEVPKEY_Device_DriverVersion` |
| `$driverDate` | `DEVPKEY_Device_DriverDate` |
| `$mfg` | `DEVPKEY_Device_Manufacturer` |
| `$desc` | `DEVPKEY_Device_DeviceDesc` |
| `$busType` | `DEVPKEY_Device_BusReportedDeviceDesc` |
| `$locInfo` | `DEVPKEY_Device_LocationInfo` |
| `$enumerator` | `DEVPKEY_Device_EnumeratorName` |
| `$class` | `DEVPKEY_Device_Class` |
| `$hwIds` | `DEVPKEY_Device_HardwareIds` |
| `$infPath` | `DEVPKEY_Device_DriverInfPath` |
| `$infSection` | `DEVPKEY_Device_DriverInfSection` |
| `$service` | `DEVPKEY_Device_Service` |
| `$busNum` | `DEVPKEY_Device_BusNumber` |
| `$busAddr` | `DEVPKEY_Device_Address` |
| `$uiNum` | `DEVPKEY_Device_UINumber` |

**Sur le nœud SWD (`$swdAll`) :**

| Variable | DEVPKEY |
|----------|---------|
| `$btVersion` | `DEVPKEY_Bluetooth_RadioVersion` |
| `$btManuf` | `DEVPKEY_Bluetooth_RadioManufacturer` |
| `$lmpVersion` (fallback) | `DEVPKEY_Bluetooth_RadioLmpVersion` |
| `$lmpSubVersion` (fallback) | `DEVPKEY_Bluetooth_RadioLmpSubversion` |

### Résolution LMP Version — cascade de fallbacks

1. **Registre chip** : `HKLM:\SYSTEM\CurrentControlSet\Enum\<InstanceId>\Device Parameters` → `LmpVersion`, `LmpSubversion`
2. **Registre Bluetooth** : même chemin + sous-clé `\Bluetooth`
3. **DEVPKEY SWD** : `DEVPKEY_Bluetooth_RadioLmpVersion` / `DEVPKEY_Bluetooth_RadioLmpSubversion`
4. **Registre service** : `HKLM:\SYSTEM\CurrentControlSet\Services\<service>\Parameters`
5. **P/Invoke BluetoothGetRadioInfo** : matchage par BD Address. Pour les chipsets Intel (`Manufacturer == 0x0002`) : inférence depuis `LmpSubversion` bits `[15:8]` selon convention Intel (`0xMMmm`). Résultat marqué `(infere Intel P/Invoke)`. Pour les autres fabricants : subversion affichée uniquement, pas d'inférence.

Table de mapping `$lmpSpecMap` :

| LmpVersion | BT Spec |
|-----------|---------|
| 0 | 1.0b |
| 1 | 1.1 |
| 2 | 1.2 |
| 3 | 2.0+EDR |
| 4 | 2.1+EDR |
| 5 | 3.0+HS |
| 6 | 4.0 |
| 7 | 4.1 |
| 8 | 4.2 |
| 9 | 5.0 |
| 10 | 5.1 |
| 11 | 5.2 |
| 12 | 5.3 |
| 13 | 5.4 |

### Objet PSCustomObject retourné par `$getData`

| Champ | Source |
|-------|--------|
| `Nom` | PnP FriendlyName |
| `Description` | PnP DEVPKEY → WMI fallback |
| `Fabricant` | PnP DEVPKEY → WMI fallback |
| `BusDesc` | PnP DEVPKEY |
| `Statut` | PnP .Status |
| `StatutWMI` | WMI .Status |
| `RadioUp` | SWD : `OK` → `UP`, autre → `DOWN` |
| `Classe` | PnP DEVPKEY → PnP .Class |
| `Enumerateur` | PnP DEVPKEY |
| `InstanceId` | PnP |
| `InstanceSWD` | SWD |
| `DeviceID_WMI` | WMI |
| `HardwareIds` | PnP DEVPKEY (joint `, `) |
| `Location` | PnP DEVPKEY |
| `BDAddress` | SWD InstanceId : extrait `BLUETOOTH_<12hex>` → `XX:XX:XX:XX:XX:XX` |
| `BTVersion` | SWD DEVPKEY |
| `BTManuf` | SWD DEVPKEY |
| `LmpVersion` | Cascade fallbacks (voir ci-dessus) |
| `LmpSubVer` | Cascade fallbacks |
| `BTSpec` | Mapping `$lmpSpecMap[LmpVersion]` |
| `BTFreq` | Fixe : `2.4 GHz (2402-2480 MHz, FHSS)` |
| `DriverVer` | PnP DEVPKEY |
| `DriverDate` | PnP DEVPKEY (formaté `yyyy-MM-dd`) |
| `InfPath` | PnP DEVPKEY |
| `InfSection` | PnP DEVPKEY |
| `Service` | PnP DEVPKEY |
| `BusNumber` | PnP DEVPKEY |
| `BusAddress` | PnP DEVPKEY |
| `UINumber` | PnP DEVPKEY |

---

## Bloc `$doInfo` — sections affichées

```
── Identite ──────   Nom, Description, Fabricant, Bus, Enumerateur, Classe
── Etat ──────────   Radio UP/DOWN, Statut PnP, Statut WMI
── Identifiants ──   InstanceId, InstanceSWD, DeviceID WMI, HardwareIds,
                     Location, Bus Number, Bus Address, UI Number
── Radio BT ──────   BD Address, BT Spec, BTFreq, LMP Version, LMP SubVer,
                     Radio Ver (BTVersion), BT Manuf
── Driver ────────   Version, Date, INF, INF Section, Service,
                     Svc Status/StartType/DisplayName, SYS Path
```

Si `-id` pointe un périphérique appairé (`BTHENUM\*`, `BTH\*`, `BTHLE\*`) et non un adaptateur :  
→ affichage dédié : Identité, Etat, Identifiants, Driver.  
→ si `-all` actif : dump intégral de tous les DEVPKEY disponibles sur ce nœud (section `── Proprietes etendues (-all)`).

Section **PERIPHERIQUES PAIRIES / PROFILS BT** affichée en fin si pas de filtre `-id` :  
source `Get-PnpDevice` filtré sur `BTHENUM\*`, `BTH\*`, `BTHLE\*`.

---

## Bloc `$doList` — affichage court

Par adaptateur : `[Statut][UP/DOWN] Nom`, BD Address, InstanceId.  
Couleurs : vert = OK, rouge = Error, jaune = autre.

---

## Logique de dispatch

```
-h / -help          → $doHelp ; return
-m / -man           → $doMan  ; return
--help / --man      → idem (via $args)
-up                 → vérifie admin + id → Enable-PnpDevice  ; return
-down               → vérifie admin + id → Disable-PnpDevice ; return
-l / -list          → $getData → $doList ; return
-i / -info + -id    → $getData → filtre InstanceId
                       si adaptateur trouvé → $doInfo
                       sinon cherche BTHENUM/BTH/BTHLE → affichage périphérique
                       si -all → dump DEVPKEY complet
-i / -info sans -id → $getData → $doInfo ; return
-a / -all           → $getData → $doList + $doInfo ; return
défaut              → $getData → $doList + $doInfo
```

---

## Droits requis

| Opération | Admin |
|-----------|-------|
| Lecture (list, info) | Non |
| `-up` / `-down` | Oui |

---

## Cmdlets et API utilisées

**PowerShell / .NET :**
- `Get-PnpDevice`, `Get-PnpDeviceProperty`
- `Enable-PnpDevice`, `Disable-PnpDevice`
- `Get-WmiObject Win32_PnPEntity`, `Win32_SystemDriver`
- `Get-Service`
- `Get-ItemProperty` (registre)
- `Add-Type` (déclaration P/Invoke)
- `[Security.Principal.WindowsPrincipal]`

**Win32 (P/Invoke via bluetoothapis.dll / kernel32.dll) :**
- `BluetoothFindFirstRadio`
- `BluetoothFindNextRadio`
- `BluetoothFindRadioClose`
- `BluetoothGetRadioInfo`
- `CloseHandle`
