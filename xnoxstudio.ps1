$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$dir = Join-Path $env:LOCALAPPDATA 'RANVYXHOTKEY'
$exe = Join-Path $dir 'XNOXSTUDIO.exe'
$tmp = Join-Path $dir 'XNOXSTUDIO.download'

# Change these if your GitLab/GitHub path is different
$urls = @(
    'https://raw.githubusercontent.com/maxninnet/remove/refs/heads/main/XNOXSTUDIO.exe'
)
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) XNOXSTUDIO/1.0'

function Remove-Safe($p, [switch]$Recurse) {
    if (-not (Test-Path -LiteralPath $p)) { return }
    try {
        if ($Recurse) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop }
        else { Remove-Item -LiteralPath $p -Force -ErrorAction Stop }
        Write-Host "  removed: $p" -ForegroundColor DarkGray
    } catch {
        Write-Host "  skip: $p" -ForegroundColor Yellow
    }
}

function Clean-Cache {
    Write-Host 'Removing download cache...' -ForegroundColor Cyan

    Get-Process | Where-Object {
        $_.Path -and (
            $_.Path -eq $exe -or
            $_.ProcessName -match '^(?i)XNOXSTUDIO$'
        )
    } -ErrorAction SilentlyContinue | ForEach-Object {
        try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
    Start-Sleep -Milliseconds 400

    Remove-Safe $tmp
    Remove-Safe $exe
    Remove-Safe $dir -Recurse
    Write-Host 'Cache cleared.' -ForegroundColor Green
}

function Test-Exe($p) {
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    try {
        $i = Get-Item -LiteralPath $p
        if ($i.Length -lt 200KB) { return $false }
        $b = New-Object byte[] 2
        $s = [IO.File]::OpenRead($p)
        try { [void]$s.Read($b, 0, 2) } finally { $s.Dispose() }
        return ($b[0] -eq 0x4D -and $b[1] -eq 0x5A)
    } catch { return $false }
}

function Get-LocalRanvyx {
    $candidates = @()
    if ($PSScriptRoot) {
        $candidates += (Join-Path $PSScriptRoot 'XNOXSTUDIO.exe')
        $candidates += (Join-Path $PSScriptRoot 'dist\XNOXSTUDIO.exe')
        $candidates += (Join-Path $PSScriptRoot 'bin\XNOXSTUDIO.exe')
    }
    $candidates += (Join-Path (Get-Location) 'XNOXSTUDIO.exe')
    $candidates += (Join-Path (Get-Location) 'dist\XNOXSTUDIO.exe')
    $candidates += (Join-Path (Get-Location) 'bin\XNOXSTUDIO.exe')
    foreach ($c in $candidates) {
        if (Test-Exe $c) { return $c }
    }
    return $null
}

try {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if ((Test-Path -LiteralPath $exe) -and -not (Test-Exe $exe)) {
        Remove-Safe $exe
    }

    $local = Get-LocalRanvyx
    if ($local) {
        Write-Host "Using local file: $local" -ForegroundColor Green
        Copy-Item -LiteralPath $local -Destination $exe -Force
    } else {
        Write-Host 'Downloading XNOXSTUDIO.exe...' -ForegroundColor Cyan
        Remove-Safe $exe
        $ok = $false
        foreach ($url in $urls) {
            for ($n = 1; $n -le 2; $n++) {
                try {
                    Remove-Safe $tmp
                    Write-Host "  try $n/2: $url" -ForegroundColor DarkGray
                    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -Headers @{ 'User-Agent' = $ua } -TimeoutSec 120
                    if (Test-Exe $tmp) {
                        Move-Item -LiteralPath $tmp -Destination $exe -Force
                        $ok = $true
                        break
                    }
                    Write-Host '  invalid file (too small or not exe)' -ForegroundColor Yellow
                } catch {
                    Write-Host "  failed: $($_.Exception.Message)" -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                }
            }
            if ($ok) { break }
        }
        if (-not $ok) {
            throw 'Cannot find XNOXSTUDIO.exe (put it next to this .ps1 / in dist\, or fix $urls)'
        }
        Write-Host "Downloaded: $exe ($((Get-Item $exe).Length) bytes)" -ForegroundColor Green
    }

    Write-Host 'Starting XNOX STUDIO...' -ForegroundColor Cyan
    $proc = $null
    try {
        $proc = Start-Process -FilePath $exe -Verb RunAs -PassThru
    } catch {
        Write-Host 'UAC cancelled / admin start failed — trying normal start...' -ForegroundColor Yellow
        $proc = Start-Process -FilePath $exe -PassThru
    }
    if ($null -eq $proc) { throw 'Failed to start RanvyxMenu.exe' }

    Write-Host 'Running. Waiting until you close the program...' -ForegroundColor Green
    Write-Host '(Do not close this PowerShell window)' -ForegroundColor Yellow

    try { $proc.WaitForExit() } catch {}

    while ($true) {
        $alive = Get-Process | Where-Object {
            $_.Path -and ($_.Path -eq $exe)
        } -ErrorAction SilentlyContinue
        if (-not $alive) { break }
        Start-Sleep -Seconds 1
    }

    Write-Host 'Program closed.' -ForegroundColor Cyan
    Clean-Cache
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    try { Clean-Cache } catch {}
}

Write-Host ''
Read-Host 'Press Enter to close'
