try {
    "..\Move_WinRE_Module\MoveWinRE.psd1" | Test-ModuleManifest -ErrorAction STOP -Verbose
}
catch {
    Write-Error -Message $Error[0]
}