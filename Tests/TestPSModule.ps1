try {
    "..\MoveWinRe\MoveWinRE.psd1" | Test-ModuleManifest -ErrorAction STOP -Verbose
}
catch {
    Write-Error -Message $Error[0]
}