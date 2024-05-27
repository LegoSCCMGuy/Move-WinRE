try {
    "..\MoveWinRe\Move-WinRE.psd1" | Test-ModuleManifest -ErrorAction STOP -Verbose
}
catch {
    Write-Error -Message $Error[0]
}