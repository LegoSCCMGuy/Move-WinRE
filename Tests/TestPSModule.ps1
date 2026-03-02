try {
    $manifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Move-WinRE\Move-WinRE.psd1'
    Test-ModuleManifest -Path $manifestPath -ErrorAction STOP -Verbose
}
catch {
    Write-Error -Message $Error[0]
}