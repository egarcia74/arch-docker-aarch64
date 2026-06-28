@{
    # PSScriptAnalyzer configuration for this project.
    # Wired into VS Code via "powershell.scriptAnalysis.settingsPath" in the workspace.
    ExcludeRules = @(
        # Write-Step/Info/Ok use Write-Host on purpose: these are interactive CLI
        # tools where coloured status output is the intent, not pipeline data.
        'PSAvoidUsingWriteHost'

        # Boolean helpers use the idiomatic Test-<Thing>Exists naming
        # (Test-ContainerExists / Test-ImageExists / Test-VolumeExists). The plural
        # "Exists" is deliberate and reads better than the singular form.
        'PSUseSingularNouns'

        # MD5 is used only in Build-ArchImage.ps1 to match the download against
        # ALARM's upstream-published .md5 checksum - it is NOT a security control,
        # and we cannot choose the algorithm the vendor publishes. (An inline
        # SuppressMessageAttribute works for the CLI but PowerShell Editor Services
        # does not reliably honour it for live diagnostics, so it is excluded here.)
        'PSAvoidUsingBrokenHashAlgorithms'
    )
}
