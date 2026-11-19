param(
    [ValidateSet('check', 'setup', 'android', 'device')]
    [string] $Task = 'check',
    [string] $DeviceId
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$suffix = if ($env:OS -eq 'Windows_NT') { '.bat' } else { '' }

function Find-Flutter {
    if ($env:FLUTTER_ROOT) {
        return Join-Path $env:FLUTTER_ROOT "bin/flutter$suffix"
    }
    $command = Get-Command "flutter$suffix" -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    # A linked worktree can reuse the SDK recorded by Flutter in the main checkout.
    $checkouts = @($repo)
    $gitDir = & git -C $repo rev-parse --path-format=absolute --git-common-dir
    if ($LASTEXITCODE -eq 0 -and (Split-Path -Leaf $gitDir) -eq '.git') {
        $checkouts += Split-Path -Parent $gitDir
    }
    foreach ($checkout in $checkouts) {
        $properties = Join-Path $checkout 'android/local.properties'
        if (Test-Path -LiteralPath $properties -PathType Leaf) {
            $match = Select-String -LiteralPath $properties -Pattern '^flutter\.sdk=(.+)$' |
                Select-Object -First 1
            if ($match) {
                $sdk = $match.Matches[0].Groups[1].Value.Replace('\\', '\').Replace('\:', ':')
                $candidate = Join-Path $sdk "bin/flutter$suffix"
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    return $candidate
                }
            }
        }
    }
}

function Invoke-Checked([string] $Executable, [string[]] $Arguments) {
    Write-Host "> $(Split-Path -Leaf $Executable) $($Arguments -join ' ')"
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$(Split-Path -Leaf $Executable) exited with code $LASTEXITCODE."
    }
}

if ($Task -eq 'device' -and -not $DeviceId) {
    throw 'Pass -DeviceId with an Android emulator or test device ID from flutter devices.'
}
$version = (Get-Content -LiteralPath (Join-Path $repo '.flutter-version') -Raw).Trim()
$flutter = Find-Flutter
if (-not $flutter -or -not (Test-Path -LiteralPath $flutter -PathType Leaf)) {
    throw "Flutter $version not found. Add its bin directory to PATH or set FLUTTER_ROOT to the SDK directory."
}
$dart = Join-Path (Split-Path -Parent $flutter) "dart$suffix"

$oldProxy = [Environment]::GetEnvironmentVariable('no_proxy')
$oldUpperProxy = [Environment]::GetEnvironmentVariable('NO_PROXY')
$oldSigning = $env:THINKCAPS_KEY_PROPERTIES
Push-Location -LiteralPath $repo
try {
    # Flutter connects to its test and debug processes over loopback WebSockets.
    $bypass = (@($oldProxy, $oldUpperProxy, 'localhost', '127.0.0.1', '::1') |
        Where-Object { $_ } | Select-Object -Unique) -join ','
    $env:no_proxy = $bypass
    $env:NO_PROXY = $bypass
    $env:THINKCAPS_KEY_PROPERTIES = $null

    $versionOutput = (& $flutter --version --machine) -join "`n"
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter version check exited with code $LASTEXITCODE."
    }
    # A fresh SDK can print bootstrap progress before the version JSON.
    $jsonStart = [regex]::Match($versionOutput, '(?m)^[ \t]*\{')
    if (!$jsonStart.Success) {
        throw 'Flutter did not return a machine-readable version.'
    }
    $installed = (ConvertFrom-Json -InputObject $versionOutput.Substring($jsonStart.Index)).frameworkVersion
    if ($installed -ne $version) {
        throw "Expected Flutter $version, found $installed at $flutter. Set FLUTTER_ROOT to the pinned SDK."
    }

    Invoke-Checked $flutter @('pub', 'get', '--enforce-lockfile')
    if ($Task -eq 'check' -or $Task -eq 'android') {
        Invoke-Checked $dart @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'integration_test')
        Invoke-Checked $flutter @('analyze', '--no-pub', '--fatal-infos')
        Invoke-Checked $flutter @('test', '--no-pub', '--reporter', 'expanded')
    }
    if ($Task -eq 'android') {
        Invoke-Checked $flutter @('build', 'apk', '--debug', '--no-pub')
    }
    if ($Task -eq 'device') {
        Invoke-Checked $flutter @('test', '--no-pub', '--reporter', 'expanded', '--device-id', $DeviceId, 'integration_test')
    }
} finally {
    Pop-Location
    if ($env:OS -ne 'Windows_NT') {
        $env:no_proxy = $oldProxy
    }
    $env:NO_PROXY = $oldUpperProxy
    $env:THINKCAPS_KEY_PROPERTIES = $oldSigning
}
