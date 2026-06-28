#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/_Common.ps1')
}

Describe '_Common.ps1 surface' {
    It 'defines helper <_>' -ForEach @(
        'Get-ArchConfig', 'Confirm-ArchConfig', 'Invoke-Docker', 'Invoke-ContainerScript',
        'Assert-ContainerRunning', 'Assert-Module', 'Assert-Command',
        'Test-DockerRunning', 'Test-ContainerExists', 'Test-ContainerRunning',
        'Test-ImageExists', 'Test-VolumeExists',
        'Write-Step', 'Write-Info', 'Write-Ok', 'Write-Fail'
    ) {
        Get-Command $_ -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-ArchConfig' {
    It 'derives MountPath from DevUser as /home/{user}' {
        $cfg = Get-ArchConfig
        $cfg.MountPath | Should -Be "/home/$($cfg.DevUser)"
    }
}

# Skip (don't clobber) if the developer already has a real local override file.
$localOverridePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'config/container.local.psd1'

Describe 'Get-ArchConfig local override' -Skip:(Test-Path $localOverridePath) {
    BeforeAll {
        $script:LocalPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'config/container.local.psd1'
    }
    AfterEach {
        Remove-Item $script:LocalPath -Force -ErrorAction SilentlyContinue
    }

    It 'merges local overrides over the base config, with local keys winning' {
        Set-Content -Path $script:LocalPath -Value "@{ Hostname = 'override-host'; SshHostPort = 2299 }"
        $cfg = Get-ArchConfig
        $cfg.Hostname      | Should -Be 'override-host'   # overridden
        $cfg.SshHostPort   | Should -Be 2299              # overridden
        $cfg.ContainerName | Should -Be 'arch-aarch64'    # untouched base value
    }

    It 'fails fast on an invalid override (SshHostPort out of range)' {
        Set-Content -Path $script:LocalPath -Value "@{ SshHostPort = 99999 }"
        { Get-ArchConfig } | Should -Throw -ExpectedMessage '*SshHostPort*'
    }
}

Describe 'Invoke-Docker' {
    # Shadow the native docker exe with a function that sets a controllable exit code,
    # so the exit-code-guard branch can be tested without Docker installed/running.
    # Uses a script-scoped exit code ($global:LASTEXITCODE is how the function feeds the
    # real automatic variable Invoke-Docker reads; it is whitelisted, not a custom global).
    BeforeAll {
        function docker { $global:LASTEXITCODE = $script:DockerFakeExit }
    }
    AfterAll {
        Remove-Item function:docker -ErrorAction SilentlyContinue
    }

    It 'does not throw when docker exits 0' {
        $script:DockerFakeExit = 0
        { Invoke-Docker -Arguments @('ps') -FailMessage 'should not surface' } | Should -Not -Throw
    }

    It 'throws the supplied message when docker exits non-zero' {
        $script:DockerFakeExit = 1
        { Invoke-Docker -Arguments @('ps') -FailMessage 'boom' } | Should -Throw -ExpectedMessage 'boom'
    }
}
