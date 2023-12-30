Install-Module -Name PSScriptAnalyzer -Repository PSGallery -Force -Verbose

Import-Module -Name PSScriptAnalyzer -Force

$analyzerErrors = Invoke-ScriptAnalyzer -Path "..\MoveWinRE\MoveWinRE.psm1" -Severity Error

if ($analyzerErrors.Count -gt 0)
{
    exit 1
}