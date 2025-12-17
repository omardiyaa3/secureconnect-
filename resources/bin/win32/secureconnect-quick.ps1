# SecureConnect VPN Quick Setup Script for Windows
# This script manages the SecureConnect VPN tunnel (equivalent to wg-quick on Unix)

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
$PipeName = "\\.\pipe\ProtectedPrefix\Administrators\WireGuard\$InterfaceName"

# Parse config file
function Parse-Config {
    param([string]$Path)

    $config = @{
        PrivateKey = ""
        Address = ""
        DNS = ""
        MTU = 1420
        PublicKey = ""
        Endpoint = ""
        AllowedIPs = @()
        PersistentKeepalive = 25
        # AWG obfuscation parameters
        Jc = $null
        Jmin = $null
        Jmax = $null
        S1 = $null
        S2 = $null
        H1 = $null
        H2 = $null
        H3 = $null
        H4 = $null
    }

    $section = ""
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -match '^\[(\w+)\]$') {
            $section = $Matches[1]
        } elseif ($line -match '^(\w+)\s*=\s*(.+)$') {
            $key = $Matches[1]
            $value = $Matches[2].Trim()

            switch ($key) {
                "PrivateKey" { $config.PrivateKey = $value }
                "Address" { $config.Address = $value }
                "DNS" { $config.DNS = $value }
                "MTU" { $config.MTU = [int]$value }
                "PublicKey" { $config.PublicKey = $value }
                "Endpoint" { $config.Endpoint = $value }
                "AllowedIPs" { $config.AllowedIPs = $value -split ',' | ForEach-Object { $_.Trim() } }
                "PersistentKeepalive" { $config.PersistentKeepalive = [int]$value }
                # AWG parameters
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

# Convert base64 key to hex
function Convert-KeyToHex {
    param([string]$Base64Key)
    $bytes = [Convert]::FromBase64String($Base64Key)
    return ($bytes | ForEach-Object { $_.ToString("x2") }) -join ''
}

# Start the daemon
function Start-Daemon {
    Write-Host "[#] Starting SecureConnect daemon..."

    # Check if already running
    $existing = Get-Process -Name "secureconnect-go" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "[!] Daemon already running, stopping it first..."
        Stop-Process -Name "secureconnect-go" -Force
        Start-Sleep -Seconds 1
    }

    # Start the daemon
    $process = Start-Process -FilePath $DaemonExe -ArgumentList $InterfaceName -PassThru -WindowStyle Hidden

    # Wait for pipe to be available
    $timeout = 10
    $waited = 0
    while (-not (Test-Path $PipeName) -and $waited -lt $timeout) {
        Start-Sleep -Milliseconds 500
        $waited += 0.5
    }

    if (-not (Test-Path $PipeName)) {
        throw "Daemon failed to start - pipe not available"
    }

    Write-Host "[+] Daemon started (PID: $($process.Id))"
    return $process
}

# Configure the daemon via named pipe (UAPI protocol)
function Set-Config {
    param($Config)

    Write-Host "[#] Configuring tunnel..."

    # Build UAPI config
    $uapi = "set=1`n"
    $uapi += "private_key=$(Convert-KeyToHex $Config.PrivateKey)`n"

    # AWG obfuscation parameters (if present)
    if ($Config.Jc -ne $null) { $uapi += "jc=$($Config.Jc)`n" }
    if ($Config.Jmin -ne $null) { $uapi += "jmin=$($Config.Jmin)`n" }
    if ($Config.Jmax -ne $null) { $uapi += "jmax=$($Config.Jmax)`n" }
    if ($Config.S1 -ne $null) { $uapi += "s1=$($Config.S1)`n" }
    if ($Config.S2 -ne $null) { $uapi += "s2=$($Config.S2)`n" }
    if ($Config.H1 -ne $null) { $uapi += "h1=$($Config.H1)`n" }
    if ($Config.H2 -ne $null) { $uapi += "h2=$($Config.H2)`n" }
    if ($Config.H3 -ne $null) { $uapi += "h3=$($Config.H3)`n" }
    if ($Config.H4 -ne $null) { $uapi += "h4=$($Config.H4)`n" }

    # Peer configuration
    $uapi += "public_key=$(Convert-KeyToHex $Config.PublicKey)`n"
    $uapi += "endpoint=$($Config.Endpoint)`n"
    $uapi += "persistent_keepalive_interval=$($Config.PersistentKeepalive)`n"

    foreach ($ip in $Config.AllowedIPs) {
        $uapi += "allowed_ip=$ip`n"
    }
    $uapi += "`n"

    # Send to daemon via named pipe
    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", "ProtectedPrefix\Administrators\WireGuard\$InterfaceName", [System.IO.Pipes.PipeDirection]::InOut)
    $pipe.Connect(5000)

    $writer = New-Object System.IO.StreamWriter($pipe)
    $reader = New-Object System.IO.StreamReader($pipe)

    $writer.Write($uapi)
    $writer.Flush()

    $response = $reader.ReadToEnd()

    $pipe.Close()

    if ($response -match "errno=") {
        throw "Configuration failed: $response"
    }

    Write-Host "[+] Tunnel configured"
}

# Set up Windows networking
function Set-Network {
    param($Config)

    Write-Host "[#] Configuring network..."

    # Parse address
    $addressParts = $Config.Address -split '/'
    $ipAddress = $addressParts[0]
    $prefixLength = if ($addressParts.Length -gt 1) { $addressParts[1] } else { "24" }

    # Wait for interface to appear
    $timeout = 10
    $waited = 0
    while (-not (Get-NetAdapter -Name $InterfaceName -ErrorAction SilentlyContinue) -and $waited -lt $timeout) {
        Start-Sleep -Milliseconds 500
        $waited += 0.5
    }

    # Set IP address
    Write-Host "[#] netsh interface ip set address `"$InterfaceName`" static $ipAddress 255.255.255.0"
    netsh interface ip set address "$InterfaceName" static $ipAddress 255.255.255.0

    # Set DNS
    if ($Config.DNS) {
        Write-Host "[#] netsh interface ip set dns `"$InterfaceName`" static $($Config.DNS)"
        netsh interface ip set dns "$InterfaceName" static $Config.DNS
    }

    # Add routes
    foreach ($allowedIP in $Config.AllowedIPs) {
        if ($allowedIP -eq "0.0.0.0/0") {
            # Default route with low metric
            Write-Host "[#] route add 0.0.0.0 mask 0.0.0.0 $ipAddress metric 5"
            route add 0.0.0.0 mask 0.0.0.0 $ipAddress metric 5
        } else {
            $routeParts = $allowedIP -split '/'
            $network = $routeParts[0]
            $cidr = if ($routeParts.Length -gt 1) { [int]$routeParts[1] } else { 32 }
            $mask = ([Math]::Pow(2, 32) - [Math]::Pow(2, 32 - $cidr)).ToString()
            $maskBytes = [BitConverter]::GetBytes([uint32]$mask)
            [Array]::Reverse($maskBytes)
            $subnetMask = ($maskBytes | ForEach-Object { $_.ToString() }) -join '.'

            Write-Host "[#] route add $network mask $subnetMask $ipAddress"
            route add $network mask $subnetMask $ipAddress
        }
    }

    Write-Host "[+] Network configured"
}

# Stop the daemon and clean up
function Stop-Daemon {
    Write-Host "[#] Stopping SecureConnect daemon..."

    # Stop the process
    $process = Get-Process -Name "secureconnect-go" -ErrorAction SilentlyContinue
    if ($process) {
        Stop-Process -Name "secureconnect-go" -Force
        Write-Host "[+] Daemon stopped"
    } else {
        Write-Host "[!] Daemon not running"
    }

    # Clean up routes
    Write-Host "[#] Cleaning up routes..."
    route delete 0.0.0.0 mask 0.0.0.0 2>$null

    Write-Host "[+] Cleanup complete"
}

# Main
try {
    if ($Action -eq "up") {
        if (-not (Test-Path $ConfigFile)) {
            throw "Config file not found: $ConfigFile"
        }

        $config = Parse-Config $ConfigFile
        Start-Daemon
        Set-Config $config
        Set-Network $config

        Write-Host ""
        Write-Host "[+] SecureConnect VPN is now active"

    } elseif ($Action -eq "down") {
        Stop-Daemon
        Write-Host ""
        Write-Host "[+] SecureConnect VPN disconnected"
    }

} catch {
    Write-Host "[-] Error: $_" -ForegroundColor Red
    exit 1
}
