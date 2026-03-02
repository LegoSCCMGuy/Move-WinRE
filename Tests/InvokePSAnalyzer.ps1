Install-Module -Name PSScriptAnalyzer -Repository PSGallery -Force -Verbose

Import-Module -Name PSScriptAnalyzer -Force

$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Move-WinRE\Move-WinRE.psm1'
$analyzerErrors = Invoke-ScriptAnalyzer -Path $modulePath -Severity Error

if ($analyzerErrors.Count -gt 0)
{
    exit 1
}