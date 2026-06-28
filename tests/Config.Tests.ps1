#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:ConfigPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'config/container.psd1'
    $script:Config = Import-PowerShellDataFile -Path $script:ConfigPath
}

Describe 'config/container.psd1' {
    It 'loads as a hashtable' {
        $Config | Should -BeOfType [hashtable]
    }

    It 'defines required key <_>' -ForEach @(
        'ImageName', 'ContainerName', 'Hostname', 'VolumeName', 'Platform',
        'RootfsUrl', 'Packages', 'DevUser', 'SshHostPort', 'StartSshOnBoot'
    ) {
        $Config.ContainsKey($_) | Should -BeTrue
    }

    It 'targets the arm64 platform' {
        $Config.Platform | Should -Be 'linux/arm64'
    }

    It 'declares a non-empty Packages array' {
        ($Config.Packages -is [array]) | Should -BeTrue
        $Config.Packages.Count | Should -BeGreaterThan 0
    }

    It 'points RootfsUrl at an ALARM .tar.gz' {
        $Config.RootfsUrl | Should -Match '^https?://.+\.tar\.gz$'
    }

    It 'does NOT store MountPath (it is derived from DevUser in Get-ArchConfig)' {
        $Config.ContainsKey('MountPath') | Should -BeFalse
    }
}
