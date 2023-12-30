Install-Module -Name PSScriptAnalyzer -Repository PSGallery -Force -Verbose

Import-Module -Name PSScriptAnalyzer -Force

$analyzerErrors = Invoke-ScriptAnalyzer -Path "..\Move_WinRE_Module\MoveWinRE.psm1" -Severity Error

if ($analyzerErrors.Count -gt 0)
{
    exit 1
}