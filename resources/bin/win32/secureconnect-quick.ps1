# SecureConnect VPN Quick Setup Script for Windows
param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("up", "down")]
    [string]$Action,

    [Parameter(Mandatory=$true, Position=1)]
    [string]$ConfigFile
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DaemonExe = Join-Path $ScriptDir "secureconnect-go.exe"
$InterfaceName = "SecureConnect"
$PipeName = "\\.\pipe\AmneziaWG\$InterfaceName"
$LogFile = Join-Path $env:TEMP "secureconnect.log"

function Log {
    param([string]$Message)
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Message"
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

function Parse-Config {
    param([string]$Path)
    $config = @{
        PrivateKey = ""; Address = ""; DNS = ""; PublicKey = ""; Endpoint = ""
        AllowedIPs = @(); PersistentKeepalive = 25
        Jc = $null; Jmin = $null; Jmax = $null; S1 = $null; S2 = $null
        H1 = $null; H2 = $null; H3 = $null; H4 = $null
    }
    Get-Content $Path | ForEach-Object {
        if ($_ -match '^(\w+)\s*=\s*(.+)$') {
            $key = $Matches[1]; $value = $Matches[2].Trim()
            switch ($key) {
                "PrivateKey" { $config.PrivateKey = $value }
                "Address" { $config.Address = $value }
                "DNS" { $config.DNS = $value }
                "PublicKey" { $config.PublicKey = $value }
                "Endpoint" { $config.Endpoint = $value }
                "AllowedIPs" { $config.AllowedIPs = $value -split ',' | ForEach-Object { $_.Trim() } }
                "PersistentKeepalive" { $config.PersistentKeepalive = [int]$value }
                "Jc" { $config.Jc = [int]$value }
                "Jmin" { $config.Jmin = [int]$value }
                "Jmax" { $config.Jmax = [int]$value }
                "S1" { $config.S1 = [int]$value }
                "S2" { $config.S2 = [int]$value }
                "H1" { $config.H1 = [long]$value }
                "H2" { $config.H2 = [long]$value }
                "H3" { $config.H3 = [long]$value }
                "H4" { $config.H4 = [long]$value }
            }
        }
    }
    return $config
}

function Convert-KeyToHex {
    param([string]$Base64Key)
    $bytes = [Convert]::FromBase64String($Base64Key)
    return ($bytes | ForEach-Object { $_.ToString("x2") }) -join ''
}

function Start-Daemon {
    # Kill existing
    Get-Process -Name "secureconnect-go" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 500

    # Verify files
    if (-not (Test-Path $DaemonExe)) { throw "Daemon not found" }
    if (-not (Test-Path (Join-Path $ScriptDir "wintun.dll"))) { throw "wintun.dll not found" }

    # Start daemon with separate stdout/stderr files
    $stdoutFile = Join-Path $env:TEMP "sc-daemon-out.log"
    $stderrFile = Join-Path $env:TEMP "sc-daemon-err.log"
    $process = Start-Process -FilePath $DaemonExe -ArgumentList $InterfaceName -PassThru -WorkingDirectory $ScriptDir -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile -WindowStyle Hidden

    # Wait for UAPI
    $timeout = 10; $waited = 0
    while ($waited -lt $timeout) {
        if ($process.HasExited) { throw "Daemon crashed" }
        $out = Get-Content $stdoutFile -Raw -ErrorAction SilentlyContinue
        if ($out -match "UAPI listener started") { return $process }
        Start-Sleep -Milliseconds 500
        $waited += 0.5
    }
    throw "Daemon timeout"
}

function Set-Config {
    param($Config)

    # Build UAPI
    $uapi = "set=1`n"
    $uapi += "private_key=$(Convert-KeyToHex $Config.PrivateKey)`n"
    if ($null -ne $Config.Jc) { $uapi += "jc=$($Config.Jc)`n" }
    if ($null -ne $Config.Jmin) { $uapi += "jmin=$($Config.Jmin)`n" }
    if ($null -ne $Config.Jmax) { $uapi += "jmax=$($Config.Jmax)`n" }
    if ($null -ne $Config.S1) { $uapi += "s1=$($Config.S1)`n" }
    if ($null -ne $Config.S2) { $uapi += "s2=$($Config.S2)`n" }
    if ($null -ne $Config.H1) { $uapi += "h1=$($Config.H1)`n" }
    if ($null -ne $Config.H2) { $uapi += "h2=$($Config.H2)`n" }
    if ($null -ne $Config.H3) { $uapi += "h3=$($Config.H3)`n" }
    if ($null -ne $Config.H4) { $uapi += "h4=$($Config.H4)`n" }
    $uapi += "public_key=$(Convert-KeyToHex $Config.PublicKey)`n"
    $uapi += "endpoint=$($Config.Endpoint)`n"
    $uapi += "persistent_keepalive_interval=$($Config.PersistentKeepalive)`n"
    foreach ($ip in $Config.AllowedIPs) { $uapi += "allowed_ip=$ip`n" }
    $uapi += "`n"

    # Send to pipe
    $tempFile = Join-Path $env:TEMP "sc-uapi.txt"
    [System.IO.File]::WriteAllText($tempFile, $uapi)

    $job = Start-Job -ScriptBlock {
        param($f, $p)
        cmd /c "type `"$f`" > `"$p`"" 2>&1
    } -ArgumentList $tempFile, $PipeName

    if (-not (Wait-Job $job -Timeout 10)) {
        Stop-Job $job; Remove-Job $job -Force
        throw "Config send timeout"
    }
    Remove-Job $job -Force
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

function Set-Network {
    param($Config)

    $ipAddress = ($Config.Address -split '/')[0]

    # Find adapter
    $timeout = 10; $waited = 0; $adapter = $null
    while ($waited -lt $timeout) {
        $adapter = Get-NetAdapter -Name $InterfaceName -ErrorAction SilentlyContinue
        if (-not $adapter) {
            $adapter = Get-NetAdapter | Where-Object { $_.Name -like "$InterfaceName*" } | Select-Object -First 1
        }
        if ($adapter) { break }
        Start-Sleep -Milliseconds 500
        $waited += 0.5
    }
    if (-not $adapter) { throw "Adapter not found" }

    # Set IP and DNS
    netsh interface ip set address "$($adapter.Name)" static $ipAddress 255.255.255.0 2>&1 | Out-Null
    if ($Config.DNS) {
        $dns = ($Config.DNS -split ',')[0].Trim()
        netsh interface ip set dns "$($adapter.Name)" static $dns 2>&1 | Out-Null
    }

    # Add routes for AllowedIPs
    foreach ($allowedIP in $Config.AllowedIPs) {
        $parts = $allowedIP -split '/'
        $network = $parts[0]
        $cidr = if ($parts.Length -gt 1) { [int]$parts[1] } else { 32 }

        if ($allowedIP -eq "0.0.0.0/0") {
            route add 0.0.0.0 mask 0.0.0.0 $ipAddress metric 5 2>&1 | Out-Null
        } else {
            $maskInt = [uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $cidr))
            $maskBytes = [BitConverter]::GetBytes($maskInt)
            [Array]::Reverse($maskBytes)
            $mask = ($maskBytes | ForEach-Object { $_.ToString() }) -join '.'
            route add $network mask $mask 0.0.0.0 IF $adapter.ifIndex metric 5 2>&1 | Out-Null
        }
    }
}

function Stop-Daemon {
    Get-Process -Name "secureconnect-go" -ErrorAction SilentlyContinue | Stop-Process -Force
    route delete 0.0.0.0 mask 0.0.0.0 2>$null
}

# Main
try {
    Log "Action: $Action"
    if ($Action -eq "up") {
        if (-not (Test-Path $ConfigFile)) { throw "Config not found" }
        $config = Parse-Config $ConfigFile
        Start-Daemon
        Set-Config $config
        Set-Network $config
        Log "Connected"
    } else {
        Stop-Daemon
        Log "Disconnected"
    }
} catch {
    Log "Error: $_"
    exit 1
}
