# hciconfig-W

Auteur : ps81frt  
Repo   : https://github.com/ps81frt/hciconf-W  
Requis : PowerShell 5.1+ — Windows 10/11

---

## Description

Fonction PowerShell qui liste, inspecte, active et désactive les adaptateurs Bluetooth.  
Croise trois sources : `Get-PnpDevice` (classe Bluetooth), nœuds `SWD\RADIO\BLUETOOTH_*`, et `Win32_PnPEntity` (WMI).

---

## Installation

```powershell
# Charger la fonction dans la session courante
. .\hciconf.ps1

# Ou l'ajouter à votre profil PowerShell
Add-Content $PROFILE ". C:\chemin\hciconf.ps1"
```

---

## Syntaxe

```
hciconfig                            # défaut : liste courte + détail tous les adaptateurs
hciconfig -l  | -list                # liste courte (nom, statut, BD Address, InstanceId)
hciconfig -i  | -info                # détail tous les adaptateurs
hciconfig -i  -id "<InstanceId>"     # détail un seul adaptateur
hciconfig -up   -id "<InstanceId>"   # activer un adaptateur  [admin requis]
hciconfig -down -id "<InstanceId>"   # désactiver un adaptateur  [admin requis]
hciconfig -h  | -help                # aide courte
hciconfig -m  | -man                 # manuel complet
```

> L'InstanceId contient des `&` et `\` — **toujours le quoter**.

---

## Paramètres

| Paramètre | Type | Description |
|-----------|------|-------------|
| `-l` / `-list` | switch | Liste courte |
| `-i` / `-info` | switch | Vue détaillée |
| `-a` / `-all` | switch | Tout afficher (défaut implicite) |
| `-up` | switch | Active l'adaptateur ciblé par `-id` |
| `-down` | switch | Désactive l'adaptateur ciblé par `-id` |
| `-id` | string | InstanceId de l'adaptateur cible |
| `-h` / `-help` | switch | Aide courte |
| `-m` / `-man` | switch | Manuel complet |

---

## Équivalences Linux → Windows

| Linux | Windows |
|-------|---------|
| `hciconfig` | `hciconfig` |
| `hciconfig hci0` | `hciconfig -i -id "<InstanceId>"` |
| `hciconfig -a` | `hciconfig -i` |
| `hciconfig -a hci0` | `hciconfig -i -id "<InstanceId>"` |
| `hciconfig hci0 up` | `hciconfig -up -id "<InstanceId>"` |
| `hciconfig hci0 down` | `hciconfig -down -id "<InstanceId>"` |

---

## Données collectées

### Sources

| Variable | Cmdlet | Filtre |
|----------|--------|--------|
| `$pnpAll` | `Get-PnpDevice -Class Bluetooth` | Exclut `BTHENUM\*` et `BTH\*` (profils appairés, pas les chips) |
| `$swdAll` | `Get-PnpDevice` | `InstanceId -like 'SWD\RADIO\BLUETOOTH*'` |
| `$wmiAll` | `Get-WmiObject Win32_PnPEntity` | `Caption LIKE '%Bluetooth%'` |

### Propriétés retournées par `$getData`

| Champ | Source | Clé PnP / WMI |
|-------|--------|---------------|
| `Nom` | PnP | `FriendlyName` |
| `Description` | PnP → WMI | `DEVPKEY_Device_DeviceDesc` |
| `Fabricant` | PnP → WMI | `DEVPKEY_Device_Manufacturer` |
| `BusDesc` | PnP | `DEVPKEY_Device_BusReportedDeviceDesc` |
| `Statut` | PnP | `.Status` |
| `StatutWMI` | WMI | `.Status` |
| `RadioUp` | SWD | `UP` si `Status -eq 'OK'`, sinon `DOWN` |
| `Classe` | PnP | `DEVPKEY_Device_Class` |
| `Enumerateur` | PnP | `DEVPKEY_Device_EnumeratorName` |
| `InstanceId` | PnP | `.InstanceId` |
| `InstanceSWD` | SWD | `.InstanceId` |
| `DeviceID_WMI` | WMI | `.DeviceID` |
| `HardwareIds` | PnP | `DEVPKEY_Device_HardwareIds` |
| `Location` | PnP | `DEVPKEY_Device_LocationInfo` |
| `BDAddress` | SWD | Extrait depuis `InstanceId` : `BLUETOOTH_<12 hex>` → `XX:XX:XX:XX:XX:XX` |
| `BTVersion` | SWD | `DEVPKEY_Bluetooth_RadioVersion` |
| `BTManuf` | SWD | `DEVPKEY_Bluetooth_RadioManufacturer` |
| `DriverVer` | PnP | `DEVPKEY_Device_DriverVersion` |
| `DriverDate` | PnP | `DEVPKEY_Device_DriverDate` (formaté `yyyy-MM-dd`) |

---

## Blocs internes

| Bloc | Rôle | Déclenché par |
|------|------|---------------|
| `$getData` | Collecte et fusion PnP + SWD + WMI | Tous les modes sauf `-up`/`-down`/`-help`/`-man` |
| `$doList` | Affichage court | `-l`, `-list`, défaut |
| `$doInfo` | Affichage détaillé par sections | `-i`, `-info`, défaut |
| `$doHelp` | Aide courte | `-h`, `-help` |
| `$doMan` | Manuel complet (here-string) | `-m`, `-man` |

---

## Logique de dispatch

```
-h / -help      → $doHelp ; return
-m / -man       → $doMan  ; return
-up             → vérifie admin + id → Enable-PnpDevice  ; return
-down           → vérifie admin + id → Disable-PnpDevice ; return
-l / -list      → $getData → $doList ; return
-i / -info      → $getData → (filtre -id si présent) → $doInfo ; return
défaut          → $getData → $doList + $doInfo
```

---

## Droits requis

| Opération | Admin requis |
|-----------|-------------|
| Lecture (list, info) | Non |
| `-up` / `-down` | Oui — `Enable-PnpDevice` / `Disable-PnpDevice` |

---

## Cmdlets utilisées

- `Get-PnpDevice`
- `Get-PnpDeviceProperty`
- `Enable-PnpDevice`
- `Disable-PnpDevice`
- `Get-WmiObject`
- `[Security.Principal.WindowsPrincipal]`

---

## Exemple

```powershell
# Récupérer l'InstanceId
hciconfig -l

# Résultat :
#   [OK] [UP] Intel(R) Wireless Bluetooth(R)
#        BD  : 50:E0:85:88:5F:1C
#        ID  : USB\VID_8087&PID_0029\8&2EFE0359&0&4

# Désactiver
hciconfig -down -id "USB\VID_8087&PID_0029\8&2EFE0359&0&4"

# Réactiver
hciconfig -up -id "USB\VID_8087&PID_0029\8&2EFE0359&0&4"
```
