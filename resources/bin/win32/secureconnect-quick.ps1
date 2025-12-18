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
$PipeName = "\\.\pipe\AmneziaWG\$InterfaceName"

# Log file for debugging
$LogFile = Join-Path $env:TEMP "secureconnect-debug.log"

function Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] $Message"
    Write-Host $logLine
    Add-Content -Path $LogFile -Value $logLine -ErrorAction SilentlyContinue
}

Log "=========================================="
Log "SecureConnect Script Started"
Log "Action: $Action"
Log "Config: $ConfigFile"
Log "Script Dir: $ScriptDir"
Log "Daemon: $DaemonExe"
Log "Pipe: $PipeName"
Log "=========================================="

# Parse config file
function Parse-Config {
    param([string]$Path)

    Log "Parsing config file: $Path"

    $config = @{
        PrivateKey = ""
        Address = ""
        DNS = ""
        MTU = 1420
        PublicKey = ""
        Endpoint = ""
        AllowedIPs = @()
        PersistentKeepalive = 25
        Jc = $null; Jmin = $null; Jmax = $null
        S1 = $null; S2 = $null
        H1 = $null; H2 = $null; H3 = $null; H4 = $null
    }

    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -match '^(\w+)\s*=\s*(.+)$') {
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

    Log "Config parsed - Endpoint: $($config.Endpoint), Address: $($config.Address)"
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
    Log "Starting daemon..."

    # Kill any existing daemon
    $existing = Get-Process -Name "secureconnect-go" -ErrorAction SilentlyContinue
    if ($existing) {
        Log "Killing existing daemon..."
        Stop-Process -Name "secureconnect-go" -Force
        Start-Sleep -Seconds 1
    }

    # Verify files exist
    if (-not (Test-Path $DaemonExe)) { throw "Daemon not found: $DaemonExe" }
    $wintunDll = Join-Path $ScriptDir "wintun.dll"
    if (-not (Test-Path $wintunDll)) { throw "wintun.dll not found: $wintunDll" }
    Log "Files verified"

    # Start daemon with output capture
    Log "Launching daemon process..."
    $stdoutFile = Join-Path $env:TEMP "sc-daemon-stdout.log"
    $stderrFile = Join-Path $env:TEMP "sc-daemon-stderr.log"
    $process = Start-Process -FilePath $DaemonExe -ArgumentList $InterfaceName -PassThru -WorkingDirectory $ScriptDir -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile -WindowStyle Hidden
    Log "Daemon launched with PID: $($process.Id)"

    # Wait for UAPI listener to start (Test-Path doesn't work for named pipes)
    Log "Waiting for UAPI listener..."
    $timeout = 10
    $waited = 0
    while ($waited -lt $timeout) {
        if ($process.HasExited) {
            $stdout = Get-Content $stdoutFile -Raw -ErrorAction SilentlyContinue
            $stderr = Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue
            Log "Daemon stdout: $stdout"
            Log "Daemon stderr: $stderr"
            throw "Daemon crashed (code $($process.ExitCode)): $stderr"
        }

        # Check daemon output for UAPI ready message
        $stdout = Get-Content $stdoutFile -Raw -ErrorAction SilentlyContinue
        if ($stdout -match "UAPI listener started") {
            Log "UAPI listener is ready!"
            Start-Sleep -Milliseconds 300
            return $process
        }

        Start-Sleep -Milliseconds 500
        $waited += 0.5
    }

    # Timeout - show what happened
    $stdout = Get-Content $stdoutFile -Raw -ErrorAction SilentlyContinue
    $stderr = Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue
    Log "Daemon stdout: $stdout"
    Log "Daemon stderr: $stderr"
    throw "UAPI listener not ready after ${timeout}s"
}

# Configure via UAPI with timeout
function Set-Config {
    param($Config)

    Log "Building UAPI config..."

    # Build UAPI message
    $uapi = "set=1`n"
    $uapi += "private_key=$(Convert-KeyToHex $Config.PrivateKey)`n"

    # AWG params
    if ($null -ne $Config.Jc) { $uapi += "jc=$($Config.Jc)`n" }
    if ($null -ne $Config.Jmin) { $uapi += "jmin=$($Config.Jmin)`n" }
    if ($null -ne $Config.Jmax) { $uapi += "jmax=$($Config.Jmax)`n" }
    if ($null -ne $Config.S1) { $uapi += "s1=$($Config.S1)`n" }
    if ($null -ne $Config.S2) { $uapi += "s2=$($Config.S2)`n" }
    if ($null -ne $Config.H1) { $uapi += "h1=$($Config.H1)`n" }
    if ($null -ne $Config.H2) { $uapi += "h2=$($Config.H2)`n" }
    if ($null -ne $Config.H3) { $uapi += "h3=$($Config.H3)`n" }
    if ($null -ne $Config.H4) { $uapi += "h4=$($Config.H4)`n" }

    # Peer
    $uapi += "public_key=$(Convert-KeyToHex $Config.PublicKey)`n"
    $uapi += "endpoint=$($Config.Endpoint)`n"
    $uapi += "persistent_keepalive_interval=$($Config.PersistentKeepalive)`n"
    foreach ($ip in $Config.AllowedIPs) {
        $uapi += "allowed_ip=$ip`n"
    }
    $uapi += "`n"

    Log "UAPI config built (length: $($uapi.Length) chars)"

    # Write to temp file
    $tempFile = Join-Path $env:TEMP "sc-uapi.txt"
    [System.IO.File]::WriteAllText($tempFile, $uapi)
    Log "Config written to: $tempFile"

    # Send to pipe with timeout using a background job
    Log "Sending config to pipe (with 10s timeout)..."

    $job = Start-Job -ScriptBlock {
        param($tempFile, $pipePath)
        cmd /c "type `"$tempFile`" > `"$pipePath`"" 2>&1
    } -ArgumentList $tempFile, $PipeName

    $completed = Wait-Job $job -Timeout 10

    if ($null -eq $completed) {
        Log "ERROR: Pipe write timed out after 10 seconds!"
        Stop-Job $job
        Remove-Job $job -Force
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        throw "UAPI pipe write timed out - daemon may not be accepting connections"
    }

    $result = Receive-Job $job
    Remove-Job $job -Force
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

    Log "Config sent successfully"
    Start-Sleep -Milliseconds 500
}

# Set up networking
function Set-Network {
    param($Config)

    Log "Configuring network..."

    $addressParts = $Config.Address -split '/'
    $ipAddress = $addressParts[0]
    Log "VPN IP: $ipAddress"

    # Wait for adapter (might have suffix like "SecureConnect 1")
    Log "Waiting for network adapter..."
    $timeout = 10
    $waited = 0
    $adapter = $null
    while ($waited -lt $timeout) {
        # Try exact name first
        $adapter = Get-NetAdapter -Name $InterfaceName -ErrorAction SilentlyContinue
        if (-not $adapter) {
            # Try with wildcard (SecureConnect, SecureConnect 1, etc.)
            $adapter = Get-NetAdapter | Where-Object { $_.Name -like "$InterfaceName*" } | Select-Object -First 1
        }
        if ($adapter) { break }
        Start-Sleep -Milliseconds 500
        $waited += 0.5
    }

    if (-not $adapter) {
        # List all adapters for debugging
        $allAdapters = Get-NetAdapter | Select-Object Name, InterfaceDescription, Status
        Log "Available adapters: $($allAdapters | Out-String)"
        throw "Adapter '$InterfaceName' not found after ${timeout}s"
    }
    Log "Adapter found: $($adapter.Name) - Status: $($adapter.Status)"

    # Use the actual adapter name for subsequent commands
    $adapterName = $adapter.Name

    # Set IP using actual adapter name
    Log "Setting IP address on '$adapterName'..."
    $netshResult = netsh interface ip set address "$adapterName" static $ipAddress 255.255.255.0 2>&1
    Log "netsh result: $netshResult"

    # Set DNS
    if ($Config.DNS) {
        Log "Setting DNS: $($Config.DNS)"
        netsh interface ip set dns "$adapterName" static $Config.DNS 2>&1
    }

    # Add routes
    foreach ($allowedIP in $Config.AllowedIPs) {
        if ($allowedIP -eq "0.0.0.0/0") {
            Log "Adding default route..."
            route add 0.0.0.0 mask 0.0.0.0 $ipAddress metric 5 2>&1
        }
    }

    Log "Network configured!"
}

# Stop daemon
function Stop-Daemon {
    Log "Stopping daemon..."
    $process = Get-Process -Name "secureconnect-go" -ErrorAction SilentlyContinue
    if ($process) {
        Stop-Process -Name "secureconnect-go" -Force
        Log "Daemon stopped"
    } else {
        Log "Daemon not running"
    }
    route delete 0.0.0.0 mask 0.0.0.0 2>$null
    Log "Cleanup complete"
}

# Main
try {
    if ($Action -eq "up") {
        if (-not (Test-Path $ConfigFile)) {
            throw "Config not found: $ConfigFile"
        }

        $config = Parse-Config $ConfigFile
        Start-Daemon
        Set-Config $config
        Set-Network $config

        Log "SUCCESS: VPN is now active!"
        Write-Host "[+] SecureConnect VPN is now active"

    } elseif ($Action -eq "down") {
        Stop-Daemon
        Log "SUCCESS: VPN disconnected"
        Write-Host "[+] SecureConnect VPN disconnected"
    }

} catch {
    Log "FATAL ERROR: $_"
    Write-Host "[-] Error: $_" -ForegroundColor Red
    exit 1
}
