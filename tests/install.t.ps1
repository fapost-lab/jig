# Tests for install.ps1 (task windows-support, design.md D1/D2/D11).
#
# Plain PowerShell, no Pester (design.md D11: a new dependency for one
# file). Runs only on the windows-latest CI job (.github/workflows/ci.yml) --
# every other job lacks a Windows PowerShell/Git for Windows to exercise.
# Each scenario is one function named Test-*, run through Invoke-JigTest,
# which prints `ok <name>` / `FAIL <name>` / `skip <name> (<reason>)` and
# tallies a final `N passed, M failed, K skipped` line, the same wording
# tests/run.sh's bash runner uses. Exits non-zero iff anything failed.
#
# No network: the "remote" install.sh installs jig from is a local bare
# repository built from *this* checkout, tagged v<JIG_VERSION>
# (scripts/lib/version.sh) -- the same no-network fixture pattern
# tests/install.t.sh's inst_build_remote uses for install.sh itself, handed
# to install.ps1 via -Repository/-InstallSh so the jig-install step never
# reaches GitHub. Git for Windows' own install codepath (winget / a
# downloaded installer) is deliberately not exercised: the runner already
# has git, so every scenario below takes the "Git found" branch except
# Test-MissingGitFails, which forces the "not found" branch without ever
# attempting to install anything.
#
# HOME/USERPROFILE point at one throwaway temp directory for the whole run:
# install.ps1 (through install.sh) defaults to $HOME/.local/share/jig and
# $HOME/.local/bin, and Git Bash's own $HOME follows USERPROFILE/HOME, so
# both env vars have to move together or the PowerShell and bash sides of
# one run would land in different "home" directories. The *real* per-user
# PATH registry value is genuinely mutated by install.ps1 (SetEnvironmentVariable
# 'User' is real, even for a HOME that points at a temp directory), so it is
# saved up front and restored in a `finally` around the whole run,
# independent of whether any individual test failed.

$ErrorActionPreference = 'Stop'

$script:TestsRun = 0
$script:TestsFailed = 0
$script:TestsSkipped = 0

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:InstallPs1 = Join-Path $script:RepoRoot 'install.ps1'
$script:PowerShellExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

# --- load install.ps1's functions without running the installer -------------
#
# Dot-sourced at this file's own top level, not inside a function: PowerShell
# imports a dot-sourced file's functions into the caller's scope, and a
# helper function's scope would vanish the moment it returned, taking every
# imported function with it.
#
# install.ps1 guards its own trailing `Install-Jig @JigForwardedArgs` call
# behind $env:JIG_INSTALL_NO_MAIN -- mirroring install.sh's own guard of the
# same name -- specifically so a caller can dot-source it and exercise its
# functions (including calling Install-Jig directly, with pieces of it
# overridden, per Test-MissingGitFails below) without that dot-source itself
# running the installer. The guard is set only for the duration of this one
# dot-source and restored immediately afterwards: Invoke-JigInstaller spawns
# separate `powershell.exe -File install.ps1 ...` child processes for every
# other scenario below, those processes inherit this process's environment,
# and leaving the guard set here would make every one of them silently do
# nothing instead of actually installing anything.
$script:PrevNoMain = $env:JIG_INSTALL_NO_MAIN
$env:JIG_INSTALL_NO_MAIN = '1'
try {
    . $script:InstallPs1
}
finally {
    if ($null -eq $script:PrevNoMain) {
        Remove-Item Env:\JIG_INSTALL_NO_MAIN -ErrorAction SilentlyContinue
    }
    else {
        $env:JIG_INSTALL_NO_MAIN = $script:PrevNoMain
    }
}

# --- test harness -------------------------------------------------------------

function Skip-JigTest {
    param([string]$Reason)
    throw "SKIP:$Reason"
}

function Invoke-JigTest {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Body
    )
    $script:TestsRun++
    try {
        & $Body
        Write-Host "ok $Name"
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg.StartsWith('SKIP:')) {
            $script:TestsSkipped++
            Write-Host "skip $Name ($($msg.Substring(5)))"
        }
        else {
            $script:TestsFailed++
            Write-Host "FAIL $Name"
            Write-Host "  $msg"
        }
    }
}

function Assert-JigEqual {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message (expected [$Expected], got [$Actual])"
    }
}

function Assert-JigTrue {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-JigContains {
    param([string]$Haystack, [string]$Needle, [string]$Message)
    if ($Haystack -notlike "*$Needle*") {
        throw "$Message (did not find '$Needle')"
    }
}

function New-JigTempDir {
    param([string]$Prefix = 'jig-t')
    $dir = Join-Path $script:TestTmp "$Prefix-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

# --- fixtures ------------------------------------------------------------------

# Get-JigVersion -- reads JIG_VERSION out of scripts/lib/version.sh without
# running bash, mirroring jig_declared_version's own pattern (a single
# JIG_VERSION="X.Y.Z" line).
function Get-JigVersion {
    $text = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'scripts\lib\version.sh')
    if ($text -notmatch 'JIG_VERSION="([^"]+)"') {
        throw 'could not read JIG_VERSION from scripts/lib/version.sh'
    }
    return $Matches[1]
}

# New-JigFixtureSourceTree <dir> <version> -- a minimal framework source
# tree: the real scripts/ (so the installed `scripts/jig version` runs for
# real, exactly like inst_fixture_source_tree in tests/install.t.sh), and
# skills/templates as placeholders (jig_is_source_root only checks the
# directories exist, but git does not track an empty one).
function New-JigFixtureSourceTree {
    param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][string]$Version)
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    Copy-Item -Path (Join-Path $script:RepoRoot 'scripts') -Destination (Join-Path $Dir 'scripts') -Recurse -Force
    New-Item -ItemType Directory -Path (Join-Path $Dir 'skills') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Dir 'templates') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $Dir 'skills\.gitkeep') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $Dir 'templates\.gitkeep') -Force | Out-Null
    # LF, no BOM: written with File.WriteAllText + a plain ASCII encoding
    # rather than Set-Content, which defaults to CRLF and a UTF-8 BOM on
    # Windows PowerShell 5.1 -- either would still parse under
    # jig_declared_version's sed pattern, but there is no reason to depend
    # on that when a plain byte-exact write is just as easy.
    $content = "JIG_VERSION=""$Version""`nexport JIG_VERSION`n"
    [System.IO.File]::WriteAllText((Join-Path $Dir 'scripts\lib\version.sh'), $content, [System.Text.Encoding]::ASCII)
}

# New-JigTestRemote <bare-dir> <tag> -- a bare repository reachable only on
# the local filesystem (no network, ever), one commit tagged <tag> with
# scripts/lib/version.sh matching it, on branch main -- the same shape
# tests/install.t.sh's inst_build_remote builds for install.sh.
function New-JigTestRemote {
    param([Parameter(Mandatory)][string]$BareDir, [Parameter(Mandatory)][string]$Tag)
    & git init -q --bare $BareDir
    if ($LASTEXITCODE -ne 0) { throw "git init --bare failed for $BareDir" }
    & git -C $BareDir symbolic-ref HEAD refs/heads/main

    $work = New-JigTempDir -Prefix 'remote-src'
    $version = $Tag.TrimStart('v')
    New-JigFixtureSourceTree -Dir $work -Version $version
    Push-Location -LiteralPath $work
    try {
        & git init -q .
        & git symbolic-ref HEAD refs/heads/main
        & git remote add origin $BareDir
        & git add -A
        & git -c user.name=jig -c user.email=jig@example.com commit -q -m $Tag
        & git tag -a -m $Tag $Tag
        & git push -q origin main --tags
        if ($LASTEXITCODE -ne 0) { throw "git push to $BareDir failed" }
    }
    finally {
        Pop-Location
    }
}

# --- invoking install.ps1 as a child process -----------------------------------

# Invoke-JigInstaller <args...> -- runs install.ps1 the way a real user's
# `-File` invocation does (tests/install.t.ps1's own subject under test),
# always through the fixed Windows PowerShell 5.1 path rather than whatever
# `powershell`/`pwsh` PATH happens to resolve, so a test that strips PATH
# (Test-MissingGitFails) cannot also break the harness's own ability to
# launch the child process.
#
# $ErrorActionPreference is forced to 'Continue' around the call for the
# same reason install.ps1's own Invoke-JigNative does it (see that
# function's comment): this file sets $ErrorActionPreference = 'Stop' at
# its own top level, and merging a *native* process's stderr via `2>&1` --
# which this is, powershell.exe being just another executable from this
# process's point of view -- turns every stderr line into a terminating
# ErrorRecord under 'Stop', misreporting a perfectly successful child run
# as a crash before its exit code is ever read.
function Invoke-JigInstaller {
    param([string[]]$InstallerArgs)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $script:PowerShellExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
            -File $script:InstallPs1 @InstallerArgs 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    $text = ($out | ForEach-Object { "$_" }) -join "`n"
    return [PSCustomObject]@{ Output = $text; ExitCode = $exitCode }
}

function Get-JigDefaultScriptsDir {
    Join-Path $env:USERPROFILE '.local\share\jig\scripts'
}

function Get-JigDefaultInstallDir {
    Join-Path $env:USERPROFILE '.local\share\jig'
}

# --- unit-style tests of pure helpers -----------------------------------------

# Regression coverage for the bug this function's ordering exists to avoid:
# with the default install directory name ("...\.local\share\jig"), the
# elsewhere-form line's payload happens to end in "/jig" too, so a
# no-symlink pattern that only checked for a "/jig (" suffix would also
# match it and misread the elsewhere line's *parent* directory as PathDir.
function Test-GetJigInstalledInfoParsesAllThreeForms {
    $linked = Get-JigInstalledInfo -Line 'jig installed: C:/Users/t/.local/bin/jig -> C:/Users/t/.local/share/jig (v0.2.0)'
    Assert-JigEqual 'symlink' $linked.Kind 'linked form should parse as symlink'
    Assert-JigEqual 'C:/Users/t/.local/bin' $linked.PathDir 'linked form PathDir should be the bin directory'
    Assert-JigEqual 'C:/Users/t/.local/share/jig/scripts/jig' $linked.JigScriptPath `
        'linked form should reconstruct scripts/jig from the install dir'
    Assert-JigEqual 'v0.2.0' $linked.Ref 'linked form ref'

    $noSymlink = Get-JigInstalledInfo -Line 'jig installed: C:/Users/t/.local/share/jig/scripts/jig (v0.2.0)'
    Assert-JigEqual 'no-symlink' $noSymlink.Kind 'no-symlink form should parse as no-symlink'
    Assert-JigEqual 'C:/Users/t/.local/share/jig/scripts' $noSymlink.PathDir `
        'no-symlink form PathDir should be the scripts directory, not its parent'
    Assert-JigEqual 'C:/Users/t/.local/share/jig/scripts/jig' $noSymlink.JigScriptPath 'no-symlink form JigScriptPath'
    Assert-JigEqual 'v0.2.0' $noSymlink.Ref 'no-symlink form ref'

    $elsewhere = Get-JigInstalledInfo -Line 'jig installed: C:/Users/t/.local/share/jig (v0.2.0)'
    Assert-JigEqual 'elsewhere' $elsewhere.Kind 'elsewhere form should parse as elsewhere'
    Assert-JigTrue ($null -eq $elsewhere.PathDir) 'elsewhere form must not add anything to PATH'
    Assert-JigEqual 'C:/Users/t/.local/share/jig/scripts/jig' $elsewhere.JigScriptPath `
        "elsewhere form should still know how to run this run's own jig"
    Assert-JigEqual 'v0.2.0' $elsewhere.Ref 'elsewhere form ref'
}

# --- scenarios -----------------------------------------------------------------

function Test-GitPresentFreshInstall {
    $projectDir = New-JigTempDir -Prefix 'project'
    $result = Invoke-JigInstaller -InstallerArgs @(
        '-Yes', '-Project', $projectDir,
        '-GitName', 't', '-GitEmail', 't@example.com',
        '-InstallSh', $script:InstallShPath,
        '-Repository', $script:RemoteDir
    )
    Assert-JigEqual 0 $result.ExitCode "install should succeed:`n$($result.Output)"

    Assert-JigTrue (Test-Path (Join-Path $projectDir '.ai\config.yaml')) '.ai\config.yaml should exist'
    Assert-JigTrue (Test-Path (Join-Path $projectDir '.claude\settings.json')) '.claude\settings.json should exist'

    $commitCount = (& git -C $projectDir rev-list --count HEAD).Trim()
    Assert-JigEqual '1' $commitCount 'exactly one commit should exist after the first install'

    $lsFiles = (& git -C $projectDir ls-files -s -- .ai/scripts/jig) -join "`n"
    Assert-JigTrue ($lsFiles -match '^100755') ".ai/scripts/jig should be mode 100755 in the index, got: $lsFiles"

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    Assert-JigTrue (Test-JigPathHasEntry -PathValue $userPath -Entry (Get-JigDefaultScriptsDir)) `
        'User PATH should contain the installed jig scripts directory'

    Assert-JigContains $result.Output 'doctor:' 'jig doctor output should be shown'

    $script:FreshProjectDir = $projectDir
}

function Test-RepeatRunIsIdempotent {
    if (-not $script:FreshProjectDir) {
        Skip-JigTest 'depends on Test-GitPresentFreshInstall having run first'
    }
    $commitsBefore = (& git -C $script:FreshProjectDir rev-list --count HEAD).Trim()

    $result = Invoke-JigInstaller -InstallerArgs @(
        '-Yes', '-Project', $script:FreshProjectDir,
        '-GitName', 't', '-GitEmail', 't@example.com',
        '-InstallSh', $script:InstallShPath,
        '-Repository', $script:RemoteDir
    )
    Assert-JigEqual 0 $result.ExitCode "repeat install should succeed:`n$($result.Output)"

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entry = (Get-JigDefaultScriptsDir).TrimEnd('\', '/')
    $occurrences = @($userPath -split ';' | Where-Object { $_.TrimEnd('\', '/') -ieq $entry })
    Assert-JigEqual 1 $occurrences.Count "the jig scripts directory should appear exactly once in User PATH, found $($occurrences.Count)"

    $commitsAfter = (& git -C $script:FreshProjectDir rev-list --count HEAD).Trim()
    Assert-JigEqual $commitsBefore $commitsAfter 'a repeat run must not add a second commit'
}

function Test-ExistingRepositoryGetsNoCommit {
    $projectDir = New-JigTempDir -Prefix 'existing-repo'
    & git -C $projectDir init -q -b main
    & git -C $projectDir config user.name existing
    & git -C $projectDir config user.email existing@example.com
    Set-Content -LiteralPath (Join-Path $projectDir 'README.md') -Value '# existing' -NoNewline
    & git -C $projectDir add README.md
    & git -C $projectDir commit -q -m 'pre-existing commit'
    $commitsBefore = (& git -C $projectDir rev-list --count HEAD).Trim()

    $result = Invoke-JigInstaller -InstallerArgs @(
        '-Yes', '-Project', $projectDir,
        '-InstallSh', $script:InstallShPath,
        '-Repository', $script:RemoteDir
    )
    Assert-JigEqual 0 $result.ExitCode "install into an existing repository should succeed:`n$($result.Output)"

    $commitsAfter = (& git -C $projectDir rev-list --count HEAD).Trim()
    Assert-JigEqual $commitsBefore $commitsAfter 'installing into an existing repository must not add a commit'
}

function Test-NoInitSkipsProject {
    $projectDir = New-JigTempDir -Prefix 'noinit'
    $result = Invoke-JigInstaller -InstallerArgs @(
        '-Yes', '-NoInit', '-Project', $projectDir,
        '-InstallSh', $script:InstallShPath,
        '-Repository', $script:RemoteDir
    )
    Assert-JigEqual 0 $result.ExitCode "-NoInit install should succeed:`n$($result.Output)"
    Assert-JigTrue (-not (Test-Path (Join-Path $projectDir '.ai'))) '-NoInit must not create .ai'
}

function Test-UninstallRemovesPathAndCheckout {
    if (-not (Test-Path (Get-JigDefaultInstallDir))) {
        Skip-JigTest 'no default install directory to remove (an earlier scenario must have failed)'
    }
    $result = Invoke-JigInstaller -InstallerArgs @('-Uninstall')
    Assert-JigEqual 0 $result.ExitCode "-Uninstall should succeed:`n$($result.Output)"

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    Assert-JigTrue (-not (Test-JigPathHasEntry -PathValue $userPath -Entry (Get-JigDefaultScriptsDir))) `
        'User PATH must no longer contain the jig scripts directory after -Uninstall'
    Assert-JigTrue (-not (Test-Path (Get-JigDefaultInstallDir))) `
        '-Uninstall must remove the default install directory'
}

function Test-MissingGitFails {
    # Stripping $env:Path alone does not reach the REQ-7 branch on
    # windows-latest: Find-JigGitCommand also falls back to
    # HKLM/HKCU:\SOFTWARE\GitForWindows, which the runner's own Git for
    # Windows install sets regardless of PATH. Instead, Find-JigGitCommand
    # is redefined for the duration of this test, which is only visible to
    # an in-process call -- Invoke-JigInstaller's child `powershell.exe
    # -File` processes each dot-source install.ps1 fresh and would never
    # see it.
    #
    # The override is written with an explicit `script:` scope, not a bare
    # `function Find-JigGitCommand { ... }`: a function defined without a
    # scope modifier *inside* another function's body (this one) is created
    # in that function's own local scope by default, same rule as
    # variables. Install-Jig, though, was dot-sourced at this file's own
    # top level (see the header comment above), so its own lookup of
    # Find-JigGitCommand walks up through *script* scope, never through
    # Test-MissingGitFails's local scope -- a bare override here would
    # therefore silently do nothing and this test would pass for the wrong
    # reason (or not fail at all). `${function:script:Name}` reads and
    # writes that same script-scope slot explicitly, matching where
    # Install-Jig actually looks.
    #
    # An in-process call only works because install.ps1's `exit` is itself
    # disabled by $env:JIG_INSTALL_NO_MAIN (see the header comment on the
    # dot-source above): without that, a failing Install-Jig would tear
    # down this whole test process instead of failing one scenario.
    # Install-Jig's own messages all go through Write-Host (the Information
    # stream, 6, not the success stream), so `*>&1` merges every stream into
    # one capture, and the loop below separates the returned exit code (an
    # [int], from the success stream) from the printed text (InformationRecord
    # entries, one per Write-Host call).
    $originalFindGit = ${function:Find-JigGitCommand}
    ${function:script:Find-JigGitCommand} = { return $null }

    $prevNoMain = $env:JIG_INSTALL_NO_MAIN
    $env:JIG_INSTALL_NO_MAIN = '1'
    $raw = $null
    try {
        $raw = Install-Jig -NoGitInstall -Yes -NoInit *>&1
    }
    finally {
        if ($null -eq $prevNoMain) { Remove-Item Env:\JIG_INSTALL_NO_MAIN -ErrorAction SilentlyContinue }
        else { $env:JIG_INSTALL_NO_MAIN = $prevNoMain }
        ${function:script:Find-JigGitCommand} = $originalFindGit
    }

    $rc = $null
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($item in $raw) {
        if ($item -is [int]) {
            $rc = $item
        }
        elseif ($item -is [System.Management.Automation.InformationRecord]) {
            $lines.Add([string]$item.MessageData)
        }
        else {
            $lines.Add([string]$item)
        }
    }
    $text = $lines -join "`n"

    Assert-JigEqual 1 $rc "install with no Git and -NoGitInstall should fail:`n$text"
    Assert-JigContains $text 'gitforwindows.org' 'the failure message should point at gitforwindows.org'
}

# --- run -------------------------------------------------------------------

$script:OriginalUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$script:OriginalUserProfile = $env:USERPROFILE
$script:OriginalHome = $env:HOME

$script:TestTmp = Join-Path $env:TEMP "jig-install-test-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
New-Item -ItemType Directory -Path $script:TestTmp -Force | Out-Null
# Git Bash's own $HOME follows USERPROFILE/HOME (see header comment): both
# must move together so install.sh's $HOME/.local/... defaults, read from
# inside bash, land in the same place this test inspects from PowerShell.
$env:USERPROFILE = $script:TestTmp
$env:HOME = $script:TestTmp

try {
    $version = Get-JigVersion
    $tag = "v$version"
    $script:RemoteDir = Join-Path $script:TestTmp 'remote.git'
    New-JigTestRemote -BareDir $script:RemoteDir -Tag $tag
    $script:InstallShPath = Join-Path $script:RepoRoot 'install.sh'

    Invoke-JigTest 'GetJigInstalledInfoParsesAllThreeForms' { Test-GetJigInstalledInfoParsesAllThreeForms }
    Invoke-JigTest 'GitPresentFreshInstall' { Test-GitPresentFreshInstall }
    Invoke-JigTest 'RepeatRunIsIdempotent' { Test-RepeatRunIsIdempotent }
    Invoke-JigTest 'ExistingRepositoryGetsNoCommit' { Test-ExistingRepositoryGetsNoCommit }
    Invoke-JigTest 'NoInitSkipsProject' { Test-NoInitSkipsProject }
    Invoke-JigTest 'UninstallRemovesPathAndCheckout' { Test-UninstallRemovesPathAndCheckout }
    Invoke-JigTest 'MissingGitFails' { Test-MissingGitFails }
}
finally {
    [Environment]::SetEnvironmentVariable('Path', $script:OriginalUserPath, 'User')
    $env:USERPROFILE = $script:OriginalUserProfile
    $env:HOME = $script:OriginalHome
    Remove-Item -Recurse -Force -LiteralPath $script:TestTmp -ErrorAction SilentlyContinue
}

$script:TestsPassed = $script:TestsRun - $script:TestsFailed - $script:TestsSkipped
Write-Host ''
Write-Host "$script:TestsPassed passed, $script:TestsFailed failed, $script:TestsSkipped skipped"
if ($script:TestsFailed -gt 0) {
    exit 1
}
exit 0
