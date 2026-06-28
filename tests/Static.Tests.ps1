#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Discovery-time: one -ForEach case per script file (must exist before BeforeAll runs).
$scriptCases = Get-ChildItem (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts') -Filter *.ps1 |
    ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }

Describe 'Static analysis' {
    # Run-time paths: discovery-scope variables are not visible inside It, so set them here.
    BeforeAll {
        $script:scriptsDir  = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts'
        $script:settingsPsd = Join-Path (Split-Path -Parent $PSScriptRoot) 'config/PSScriptAnalyzerSettings.psd1'
    }

    It '<Name> parses without syntax errors' -ForEach $scriptCases {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It 'scripts pass PSScriptAnalyzer with project settings' -Skip:($null -eq (Get-Module -ListAvailable PSScriptAnalyzer)) {
        $results = Invoke-ScriptAnalyzer -Path $scriptsDir -Recurse -Settings $settingsPsd
        $results | Should -BeNullOrEmpty -Because ($results | Out-String)
    }
}
