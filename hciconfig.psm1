# 1. ExecutionPolicy — à faire une seule fois (session admin)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# 2. Téléchargement et extraction dans TEMP
Invoke-WebRequest https://github.com/ps81frt/hciconf-W/archive/refs/heads/main.zip -OutFile "$env:TEMP\hciconf-W.zip"

# 3. Déblocage du zip avant extraction (MOTW — Mark of the Web)
Unblock-File "$env:TEMP\hciconf-W.zip"

Expand-Archive "$env:TEMP\hciconf-W.zip" -DestinationPath "$env:TEMP\hciconf-W"
Remove-Item "$env:TEMP\hciconf-W.zip"

$src = "$env:TEMP\hciconf-W\hciconf-W-main\hciconfig.psm1"

# 4. Déblocage du .psm1 extrait
Unblock-File $src

# 5. Création des deux dossiers dans tous les cas (PS7 absent = dossier prêt pour plus tard)
$dest51 = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\hciconfig"
$dest7  = "$env:USERPROFILE\Documents\PowerShell\Modules\hciconfig"
New-Item -ItemType Directory -Force -Path $dest51 | Out-Null
New-Item -ItemType Directory -Force -Path $dest7  | Out-Null

# 6. Copie avec confirmation si déjà installé
foreach ($dest in @($dest51, $dest7)) {
    $target = "$dest\hciconfig.psm1"
    if (Test-Path $target) {
        $rep = Read-Host "  [!] Deja installe dans $dest`n      Ecraser ? (o/N)"
        if ($rep -notmatch '^[oO]$') {
            Write-Host "  [--] Ignore : $dest" -ForegroundColor Yellow
            continue
        }
    }
    Copy-Item $src $target -Force
    Unblock-File $target
    Write-Host "  [OK] Installe : $dest" -ForegroundColor Green
}

# 7. Nettoyage TEMP
Remove-Item "$env:TEMP\hciconf-W" -Recurse
