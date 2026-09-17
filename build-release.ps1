# Compatible with Windows PowerShell 5.1 and PowerShell 7.
# Usage: powershell -ExecutionPolicy Bypass -File .\build-release.ps1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $projectDir = $PSScriptRoot
    $buildDir = Join-Path $projectDir 'build'
    $exePath = Join-Path $buildDir 'Release\paping.exe'
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'

    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw 'Visual Studio Installer was not found. Install the Visual Studio C++ Desktop Development tools.'
    }

    $vsJson = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json
    if ($LASTEXITCODE -ne 0) { throw 'Unable to query the Visual Studio installation.'  }
    $installations = @(($vsJson -join "`n") | ConvertFrom-Json)
    if ($installations.Count -eq 0) {
        throw 'MSVC x64 compiler not found. Install the Visual Studio C++ Desktop Development tools.'
    }
    $installation = $installations[0]
    $vsMajor = ([version]$installation.installationVersion).Major

    $cmakePath = Join-Path $installation.installationPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    if (-not (Test-Path -LiteralPath $cmakePath)) {
        $cmakeCommand = Get-Command cmake.exe -ErrorAction SilentlyContinue
        if ($null -eq $cmakeCommand) {
            throw 'CMake was not found. Install the C++ CMake tools for Windows using Visual Studio Installer.'
        }
        $cmakePath = $cmakeCommand.Source
    }

    $capabilitiesJson = & $cmakePath -E capabilities
    if ($LASTEXITCODE -ne 0) { throw 'Failed to read CMake capabilities.' }
    $capabilities = ($capabilitiesJson -join "`n") | ConvertFrom-Json
    $generators = @($capabilities.generators | Where-Object { $_.name -like "Visual Studio $vsMajor *" })
    if ($generators.Count -eq 0) {
        throw "CMake does not support Visual Studio $vsMajor version. Update your CMake tools."
    }
    $generator = $generators[0].name

    Write-Host "CMake: $cmakePath"
    Write-Host "Compiler: $generator (x64)"
    & $cmakePath -S $projectDir -B $buildDir -G $generator -A x64 "-DCMAKE_GENERATOR_INSTANCE=$($installation.installationPath)"
    if ($LASTEXITCODE -ne 0) { throw 'CMake configuration failed. Check the error details above.' }

    & $cmakePath --build $buildDir --config Release --parallel
    if ($LASTEXITCODE -ne 0) { throw 'Release build failed.' }
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        throw "Build completed, but the EXE was not found: $exePath"
    }

    Write-Host "`nWindows x64 Release EXE is ready: $exePath" -ForegroundColor Green
    exit 0
}
catch {
    [Console]::Error.WriteLine("Error: {0}", $_.Exception.Message)
    exit 1
}
