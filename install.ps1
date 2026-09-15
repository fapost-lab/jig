# Jig remote installer for Windows (task windows-support, design.md D1/D2).
#
# Bootstraps Git for Windows (if missing), the global `jig` framework
# checkout via install.sh, and (with consent) a first project -- for someone
# who has never used git, from one line pasted into PowerShell:
#
#   irm https://raw.githubusercontent.com/fapost-lab/jig/main/install.ps1 | iex
#
# ADR-0002 restricts jig's own logic to bash/git; this file is the one
# permitted exception, the Windows-only bootstrapper that gets a real bash
# onto the machine so the rest of jig never has to be ported (design.md D1).
# It never talks to a project's runtime config beyond what `jig init` itself
# does (ADR-0024), and it deletes only what *this run* created (RULES.md,
# ADR-0033): a downloaded Git installer, if any.
#
# Compatible with Windows PowerShell 5.1 as well as PowerShell 7: no `?.`,
# `??`, the `? :` ternary operator, `&&`/`||` pipeline chains, or
# `-AsHashtable`. `Invoke-RestMethod`'s default JSON parsing (a PSObject) is
# used instead of the PS7-only `-AsHashtable` switch.
#
# --- invocation and truncation safety ----------------------------------------
#
# `irm ... | iex` pipes this file's *text* into Invoke-Expression, which
# evaluates it in the caller's own scope -- not as a script file. A `param()`
# block at the top of that text therefore never binds to anything; there is
# no invocation for it to bind against. Every parameter instead lives on the
# `Install-Jig` function below, and the very last line is the only place that
# function is called (mirroring install.sh's own function-per-behaviour
# structure and its comment on why: nothing above that call has any effect on
# its own).
#
# PowerShell parses a script (or a string handed to Invoke-Expression) in
# full before executing any part of it: a syntax error anywhere -- including
# an unterminated function body from a transfer cut short mid-stream -- is
# raised before the first statement runs, not after. That is a stronger
# guarantee than install.sh needs its final compound `if` for (bash can start
# executing a truncated stream up to the point of failure); here, nothing
# above the last line ever runs unless the whole file parsed.

function Write-JigStep {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "==> $Message"
}

function Write-JigResult {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "    $Message"
}

# The one message shown for every "Git for Windows is unusable and we could
# not fix it ourselves" outcome (REQ-7): what happened is different each
# time (no winget, no network, UAC declined, -NoGitInstall, no bash next to
# git), but the fix is always the same, and a vibe coder reading five
# different stack traces would just close the window.
#
# A function, not a `$script:`-scoped variable: `$script:` names the scope
# of the currently running *script*, which is well-defined when this file
# runs as `-File install.ps1`, but `irm ... | iex` evaluates this text with
# Invoke-Expression in the caller's own (interactive, top-level) scope,
# where there is no script of its own for `$script:` to bind to. A function
# call has no such ambiguity in either context.
function Get-JigGitMissingMessage {
    'Git for Windows could not be installed automatically. ' `
        + 'Install it yourself from https://gitforwindows.org, then run the same line again.'
}

# --- pure helpers (no I/O; safe to dot-source and call directly in tests) ---

# ConvertTo-JigBashPath <path> -- a Windows path with forward slashes, the
# form Git Bash's MSYS runtime accepts for an absolute Windows path
# (scripts/jig.cmd's own comment: "Bash wants forward slashes"). Never
# rewritten to /c/... form: MSYS accepts "C:/Users/..." directly, and this
# avoids a second, drive-letter-specific transform.
function ConvertTo-JigBashPath {
    param([Parameter(Mandatory)][string]$Path)
    $Path.Replace('\', '/')
}

# Test-JigPathHasEntry <PathValue> <Entry> -- whether a `;`-joined PATH
# string already contains <Entry>, case-insensitively and ignoring a
# trailing slash or backslash, so a repeat run never appends a duplicate
# that differs only in case or a trailing separator.
function Test-JigPathHasEntry {
    param(
        [AllowEmptyString()][string]$PathValue,
        [Parameter(Mandatory)][string]$Entry
    )
    if ([string]::IsNullOrEmpty($PathValue)) {
        return $false
    }
    $target = $Entry.TrimEnd('\', '/')
    foreach ($part in ($PathValue -split ';')) {
        if ($part.TrimEnd('\', '/') -ieq $target) {
            return $true
        }
    }
    return $false
}

# Get-JigInstalledInfo <line> -- parses install.sh's one-line summary
# (install.sh's own three `printf 'jig installed: ...'` forms, see its
# main()) into: Ref; JigScriptPath, this run's own scripts/jig, always set
# and always runnable through bash regardless of what happens to PATH; and
# PathDir, the directory that belongs on the User PATH, or $null when
# nothing this run made belongs there (install.sh preserved a symlink
# elsewhere).
#
# Checked in this order, and the order matters: the linked form is tried
# first because " -> " appears in no other form. The no-symlink form
# requires a literal "/scripts/jig (" suffix -- not just "/jig (" -- because
# the *elsewhere* form's payload is a bare install directory, and with the
# default install directory name ("...\.local\share\jig") that bare
# directory itself ends in "/jig". A looser "/jig (" pattern for the
# no-symlink form would therefore also match an elsewhere line and misread
# its *parent* directory as PathDir -- one level too high, and a directory
# rather than the jig script itself. Requiring "/scripts/jig (" cannot
# collide with the elsewhere form unless an install directory is itself
# named "...\scripts\jig", which install.ps1 never produces (it never
# passes --install-dir to install.sh).
function Get-JigInstalledInfo {
    param([Parameter(Mandatory)][string]$Line)

    if ($Line -notmatch '^jig installed: ') {
        throw "not an install.sh summary line: $Line"
    }
    $rest = $Line -replace '^jig installed: ', ''

    if ($rest -match '^(?<bin>.+) -> (?<install>.+) \((?<ref>[^()]*)\)$') {
        $binJig = $Matches['bin']
        if (-not $binJig.EndsWith('/jig')) {
            throw "unexpected 'jig installed:' line (bin path): $Line"
        }
        $pathDir = $binJig.Substring(0, $binJig.Length - 4)
        $jigScriptPath = "$($Matches['install'])/scripts/jig"
        return [PSCustomObject]@{ PathDir = $pathDir; JigScriptPath = $jigScriptPath; Ref = $Matches['ref']; Kind = 'symlink' }
    }
    if ($rest -match '^(?<checkout>.+)/scripts/jig \((?<ref>[^()]*)\)$') {
        $checkout = $Matches['checkout']
        return [PSCustomObject]@{ PathDir = "$checkout/scripts"; JigScriptPath = "$checkout/scripts/jig"; Ref = $Matches['ref']; Kind = 'no-symlink' }
    }
    if ($rest -match '^(?<install>.+) \((?<ref>[^()]*)\)$') {
        # install.sh preserved a symlink pointing at a *different* checkout
        # (SYMLINK_ELSEWHERE). $Matches['install'] is still *this run's own*
        # checkout (install.sh's own $INSTALL_DIR), so its scripts/jig is a
        # perfectly usable jig for the rest of this run -- it is only PATH
        # that gains nothing, because the pre-existing symlink elsewhere
        # presumably already resolves to something usable.
        return [PSCustomObject]@{ PathDir = $null; JigScriptPath = "$($Matches['install'])/scripts/jig"; Ref = $Matches['ref']; Kind = 'elsewhere' }
    }
    throw "could not parse install.sh output line: $Line"
}

# --- native process invocation -----------------------------------------------

# Invoke-JigNative <file> [<args>] -- runs a native executable with
# $ErrorActionPreference locally forced to 'Continue', regardless of
# whatever the caller's own preference is set to (a user's PowerShell
# profile may set it to 'Stop' before running this file as `-File`, and
# tests/install.t.ps1 dot-sources this file into a scope that already has
# it set to 'Stop'). On Windows PowerShell 5.1, merging a native command's
# stderr into the success stream (`2>&1`) turns *every* stderr line --
# including ordinary progress or warning text such as git's "Cloning
# into..." or "warning: LF will be replaced by CRLF" -- into a
# non-terminating ErrorRecord; under $ErrorActionPreference = 'Stop', the
# very first such line then throws before $LASTEXITCODE is ever read,
# misreporting a perfectly successful command as a crash. Every native call
# in this file goes through here so that success is decided only by
# $LASTEXITCODE, never by whether an exception happened to be thrown.
function Invoke-JigNative {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$NativeArgs = @()
    )
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $raw = & $FilePath @NativeArgs 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    # Each element of $raw is either a plain string (stdout) or an
    # ErrorRecord (redirected stderr); "$_" renders either as its text, so
    # callers always get a flat array of strings regardless of which stream
    # a given line came from.
    $lines = @($raw | ForEach-Object { "$_" })
    return [PSCustomObject]@{ Output = $lines; ExitCode = $exitCode }
}

# --- step 1/4: Git for Windows and its bash ----------------------------------

# Find-JigGitCommand -- git.exe's full path, from PATH first, then the
# registry Git for Windows itself writes (HKLM, then HKCU: a per-machine
# install is more common, but a per-user one is what /CURRENTUSER makes).
# Never just "git": a caller needs the real path to derive --exec-path and
# to put git's own directory on PATH before anything shells out to it.
function Find-JigGitCommand {
    $cmd = Get-Command git -CommandType Application -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    foreach ($hive in 'HKLM:\SOFTWARE\GitForWindows', 'HKCU:\SOFTWARE\GitForWindows') {
        if (-not (Test-Path $hive)) {
            continue
        }
        $prop = Get-ItemProperty -Path $hive -Name InstallPath -ErrorAction SilentlyContinue
        if (-not $prop -or -not $prop.InstallPath) {
            continue
        }
        $exe = Join-Path $prop.InstallPath 'bin\git.exe'
        if (Test-Path $exe) {
            return $exe
        }
    }
    return $null
}

# Update-JigSessionPath -- refreshes $env:Path from the Machine and User
# environment (REQ-4): whatever Git's installer or our own PATH write just
# did, without needing a new terminal.
function Update-JigSessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @($machine, $user) | Where-Object { $_ }
    $env:Path = ($parts -join ';')
}

# Find-JigBash <git-exe> -- bash.exe resolved from `git --exec-path`, never
# from PATH: PATH's "bash" can be C:\Windows\System32\bash.exe, the WSL
# launcher, which is not a usable bash for this repo (scripts/jig.cmd's own
# comment, and design.md D1 step 4).
function Find-JigBash {
    param([Parameter(Mandatory)][string]$GitExe)
    $result = Invoke-JigNative -FilePath $GitExe -NativeArgs @('--exec-path')
    if ($result.ExitCode -ne 0 -or $result.Output.Count -eq 0) {
        return $null
    }
    $execPath = $result.Output | Select-Object -First 1
    $bash = [System.IO.Path]::GetFullPath((Join-Path $execPath '..\..\..\bin\bash.exe'))
    if (Test-Path $bash) {
        return $bash
    }
    return $null
}

# Find-JigCygpath <bash-exe> -- cygpath.exe under the same Git for Windows
# root as <bash-exe> (bin\bash.exe and usr\bin\cygpath.exe are siblings one
# level up), used to turn the MSYS-form paths install.sh prints back into
# paths PowerShell/.NET understands. $null when absent, so the caller can
# fall back to running cygpath through bash itself.
function Find-JigCygpath {
    param([Parameter(Mandatory)][string]$BashExe)
    $root = Split-Path -Parent (Split-Path -Parent $BashExe)
    $cyg = Join-Path $root 'usr\bin\cygpath.exe'
    if (Test-Path $cyg) {
        return $cyg
    }
    return $null
}

# ConvertFrom-JigMsysPath <bash-exe> <msys-path> -- <msys-path> (as printed
# by install.sh, built with `pwd -P` inside Git Bash) converted to a Windows
# path via cygpath -w.
function ConvertFrom-JigMsysPath {
    param(
        [Parameter(Mandatory)][string]$BashExe,
        [Parameter(Mandatory)][string]$MsysPath
    )
    $cyg = Find-JigCygpath -BashExe $BashExe
    if ($cyg) {
        $result = Invoke-JigNative -FilePath $cyg -NativeArgs @('-w', $MsysPath)
    }
    else {
        $result = Invoke-JigNative -FilePath $BashExe -NativeArgs @('-c', "cygpath -w '$MsysPath'")
    }
    if ($result.ExitCode -ne 0 -or $result.Output.Count -eq 0) {
        throw "could not convert path via cygpath: $MsysPath"
    }
    return ($result.Output | Select-Object -Last 1).Trim()
}

# Invoke-JigCommand -- runs the installed `jig` (the bash dispatcher, never
# executed directly: its shebang and executable bit are exactly what REQ-15
# says Windows checkouts cannot be trusted to keep) through bash explicitly,
# the same pattern scripts/jig.cmd uses. <WorkingDirectory>, when given,
# becomes jig's cwd via PowerShell's own location -- bash.exe inherits it --
# because bash has no "-C <dir>" of its own.
function Invoke-JigCommand {
    param(
        [Parameter(Mandatory)][string]$BashExe,
        [Parameter(Mandatory)][string]$JigScriptPath,
        [string]$WorkingDirectory,
        [string[]]$JigArgs = @()
    )
    $bashJig = ConvertTo-JigBashPath $JigScriptPath
    $pushed = $false
    if ($WorkingDirectory) {
        Push-Location -LiteralPath $WorkingDirectory
        $pushed = $true
    }
    try {
        $result = Invoke-JigNative -FilePath $BashExe -NativeArgs (@($bashJig) + $JigArgs)
    }
    finally {
        if ($pushed) {
            Pop-Location
        }
    }
    return $result
}

# --- step 2: installing Git for Windows --------------------------------------

# Install-JigGitViaDownloadedInstaller -- the no-winget path (REQ-2/3):
# download the latest git-for-windows/git release's 64-bit installer and run
# it silently, elevated. If the UAC prompt is declined (Win32Exception,
# NativeErrorCode 1223 -- "the operation was canceled by the user"), retry
# the same installer with /CURRENTUSER, which needs no elevation. Deletes
# only the installer file this run itself downloaded (RULES.md), win or
# lose, via `finally`.
#
# Every failure mode here -- no network to GitHub, no matching release
# asset, or the installer itself failing -- is caught and reported with one
# Write-JigResult line, and the function then simply returns without having
# installed git, instead of throwing. That lets the caller's own re-check of
# Find-JigGitCommand decide what happens next: if this attempt genuinely
# left a usable git behind, the caller finds it; otherwise the single REQ-7
# message is what the user sees, rather than a raw exception from wherever
# this attempt happened to give up.
function Install-JigGitViaDownloadedInstaller {
    $downloaded = $null
    try {
        Write-JigStep 'Downloading the Git for Windows installer...'
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest' `
            -Headers @{ 'User-Agent' = 'jig-install.ps1' } -ErrorAction Stop
        $asset = $release.assets | Where-Object { $_.name -like 'Git-*-64-bit.exe' } | Select-Object -First 1
        if (-not $asset) {
            Write-JigResult 'no Git-*-64-bit.exe asset found on the latest release'
            return
        }
        $downloaded = Join-Path $env:TEMP $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloaded -ErrorAction Stop
        Write-JigResult "downloaded: $($asset.name)"

        Write-JigStep 'Installing Git for Windows (a permission prompt may appear)...'
        $proc = $null
        $currentUserOnly = $false
        try {
            $proc = Start-Process -FilePath $downloaded -ArgumentList '/VERYSILENT', '/NORESTART' -Verb RunAs -Wait -PassThru
        }
        catch [System.ComponentModel.Win32Exception] {
            if ($_.Exception.NativeErrorCode -ne 1223) {
                throw
            }
            Write-JigResult 'permission declined; installing for the current user only'
            $currentUserOnly = $true
            $proc = Start-Process -FilePath $downloaded -ArgumentList '/VERYSILENT', '/NORESTART', '/CURRENTUSER' -Wait -PassThru
        }
        # -PassThru's ExitCode is the only reliable success signal here:
        # /VERYSILENT shows no UI to fail visibly on, so without checking
        # it, a corrupted download or a blocked installer would be reported
        # as "installed" even though git never actually landed.
        if (-not $proc -or $proc.ExitCode -ne 0) {
            $code = if ($proc) { $proc.ExitCode } else { 'unknown' }
            Write-JigResult "the installer reported a failure (exit code $code)"
            return
        }
        if ($currentUserOnly) {
            Write-JigResult 'installed for the current user'
        }
        else {
            Write-JigResult 'installed'
        }
    }
    catch {
        Write-JigResult "could not install Git for Windows this way: $($_.Exception.Message)"
    }
    finally {
        if ($downloaded -and (Test-Path $downloaded)) {
            Remove-Item -Force -LiteralPath $downloaded -ErrorAction SilentlyContinue
        }
    }
}

# Install-JigGitForWindows -- winget first (REQ-2), the downloaded installer
# as fallback, refreshing PATH after each attempt so the next check sees it.
function Install-JigGitForWindows {
    Write-Host 'Git for Windows is needed. Windows will ask for permission once.'
    $winget = Get-Command winget -CommandType Application -ErrorAction SilentlyContinue
    if ($winget) {
        Write-JigStep 'Installing Git for Windows via winget...'
        $wingetResult = Invoke-JigNative -FilePath 'winget' -NativeArgs @(
            'install', '--id', 'Git.Git', '-e', '--source', 'winget', '--silent',
            '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
        )
        $wingetResult.Output | ForEach-Object { Write-Host $_ }
        Update-JigSessionPath
        if (Find-JigGitCommand) {
            Write-JigResult 'installed via winget'
            return
        }
        Write-JigResult 'winget did not leave a usable git; falling back to a direct download'
    }
    Install-JigGitViaDownloadedInstaller
    Update-JigSessionPath
}

# --- step 5: installing jig itself -------------------------------------------

# Get-JigInstallScript -InstallSh <path> -- a local install.sh, used as-is
# (for tests and support: no network). Without it, install.sh is downloaded
# fresh from `main` -- always the latest bootstrapper, independent of
# whichever release tag it will go on to install (ADR-0033: install.sh
# itself is not part of the release-tag channel).
function Get-JigInstallScript {
    param([string]$InstallSh)
    if ($InstallSh) {
        if (-not (Test-Path $InstallSh)) {
            throw "-InstallSh does not exist: $InstallSh"
        }
        return (Resolve-Path -LiteralPath $InstallSh).Path
    }
    $dest = Join-Path $env:TEMP 'jig-install.sh'
    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/fapost-lab/jig/main/install.sh' `
        -OutFile $dest -ErrorAction Stop
    return $dest
}

# Add-JigUserPath <dir> -- <dir> onto the User PATH (no admin rights needed,
# REQ-3) and the current session, only when it is not already present
# (case/trailing-slash-insensitive), so a repeat run never grows PATH.
function Add-JigUserPath {
    param([Parameter(Mandatory)][string]$Dir)
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (Test-JigPathHasEntry -PathValue $current -Entry $Dir)) {
        $new = if ([string]::IsNullOrEmpty($current)) { $Dir } else { "$current;$Dir" }
        [Environment]::SetEnvironmentVariable('Path', $new, 'User')
    }
    if (-not (Test-JigPathHasEntry -PathValue $env:Path -Entry $Dir)) {
        $env:Path = if ([string]::IsNullOrEmpty($env:Path)) { $Dir } else { "$env:Path;$Dir" }
    }
}

# Install-JigFramework -- runs install.sh --no-path under bash (D5: the
# no-symlink fallback is what makes --no-path installable at all on a
# machine without symlink rights) and folds its one-line summary into a
# PATH change. JigScript is always set on the object this returns (Get-
# JigInstalledInfo's JigScriptPath, converted to a Windows path): even when
# install.sh preserved a symlink elsewhere and nothing this run made
# belongs on PATH, this run's own checkout is still a perfectly usable jig
# for the rest of this run to set up a project with.
function Install-JigFramework {
    param(
        [Parameter(Mandatory)][string]$BashExe,
        [Parameter(Mandatory)][string]$InstallShPath,
        [string]$Ref,
        [string]$Repository
    )
    $bashArgs = @((ConvertTo-JigBashPath $InstallShPath), '--no-path')
    if ($Ref) { $bashArgs += @('--ref', $Ref) }
    if ($Repository) {
        # Forward slashes either way: a no-op for a URL (it has none), and
        # required for a local Windows path -- install.sh's own D9 fix
        # compares local --repository values as physical directories, which
        # needs a path bash's `cd` can actually resolve.
        $bashArgs += @('--repository', (ConvertTo-JigBashPath $Repository))
    }

    $result = Invoke-JigNative -FilePath $BashExe -NativeArgs $bashArgs
    $result.Output | ForEach-Object { Write-Host $_ }
    if ($result.ExitCode -ne 0) {
        throw 'installing jig failed (see the output above and the log)'
    }

    $installedLine = $result.Output | Where-Object { $_ -match '^jig installed: ' } | Select-Object -Last 1
    if (-not $installedLine) {
        throw "install.sh did not print a 'jig installed:' summary line"
    }
    $info = Get-JigInstalledInfo -Line $installedLine
    $winJigScript = ConvertFrom-JigMsysPath -BashExe $BashExe -MsysPath $info.JigScriptPath
    if ($info.PathDir) {
        $winPathDir = ConvertFrom-JigMsysPath -BashExe $BashExe -MsysPath $info.PathDir
        Add-JigUserPath -Dir $winPathDir
    }
    else {
        Write-JigResult "jig is already on PATH from another checkout; using this run's own copy directly ($winJigScript) without changing PATH"
    }
    return [PSCustomObject]@{ JigScript = $winJigScript; Ref = $info.Ref }
}

# --- step 6: the first project -----------------------------------------------

# Invoke-JigGitOrThrow <git-exe> <description> <git-args> -- runs git
# through Invoke-JigNative and throws a plain-English message -- the step
# being attempted plus git's own last line of output -- on a non-zero exit,
# instead of silently continuing with a half-finished repository. Every git
# call in Initialize-JigProject that is *not* allowed to fail (unlike, say,
# checking whether a folder is already a repository, or whether an identity
# is already set) goes through here.
function Invoke-JigGitOrThrow {
    param(
        [Parameter(Mandatory)][string]$GitExe,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string[]]$GitArgs
    )
    $result = Invoke-JigNative -FilePath $GitExe -NativeArgs $GitArgs
    if ($result.ExitCode -ne 0) {
        $lastLine = $result.Output | Select-Object -Last 1
        throw "$Description`: $lastLine"
    }
    return $result.Output
}

# Read-JigConfirm <prompt> -- a yes/no question, defaulting to yes and
# skipped (answered yes) under -Yes (design.md D2: at most four questions,
# and -Yes takes every default).
function Read-JigConfirm {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [bool]$Yes
    )
    if ($Yes) {
        return $true
    }
    $answer = Read-Host "$Prompt [Y/n]"
    if ([string]::IsNullOrWhiteSpace($answer)) {
        return $true
    }
    return $answer -match '^[Yy]'
}

function Read-JigValue {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Default
    )
    $label = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
    $val = Read-Host $label
    if ([string]::IsNullOrWhiteSpace($val)) {
        return $Default
    }
    return $val
}

# Initialize-JigProject -- REQ-8..11 / design.md D2, at most four questions.
# Returns the project directory jig was set up in, or $null when it was
# skipped (declined git-init, or the "set up jig?" question was declined).
function Initialize-JigProject {
    param(
        [string]$Project,
        [bool]$Yes,
        [string]$GitName,
        [string]$GitEmail,
        [Parameter(Mandatory)][string]$GitExe,
        [Parameter(Mandatory)][string]$BashExe,
        [Parameter(Mandatory)][string]$JigScriptPath
    )

    # Q1: project folder.
    $projectDir = $Project
    if (-not $projectDir) {
        if ($Yes) {
            $projectDir = (Get-Location).Path
        }
        else {
            $projectDir = Read-JigValue -Prompt 'Project folder' -Default (Get-Location).Path
        }
    }
    $projectDir = [System.IO.Path]::GetFullPath($projectDir)
    if (-not (Test-Path -LiteralPath $projectDir)) {
        New-Item -ItemType Directory -Path $projectDir -Force | Out-Null
    }

    # What was here before jig touched anything (REQ-9: shown before the
    # first commit swallows it into history), captured now so later steps
    # (git init, jig init) cannot already have added to it.
    $preExisting = @(Get-ChildItem -LiteralPath $projectDir -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\\.git(\\|$)' } |
        ForEach-Object { $_.FullName.Substring($projectDir.Length).TrimStart('\', '/') })

    # Q2: make it a git repository.
    $repoCheck = Invoke-JigNative -FilePath $GitExe -NativeArgs @('-C', $projectDir, 'rev-parse', '--is-inside-work-tree')
    $isRepo = ($repoCheck.ExitCode -eq 0)
    $repoCreatedThisRun = $false
    if (-not $isRepo) {
        Write-Host ''
        if (Read-JigConfirm -Prompt 'Make this folder a git repository?' -Yes $Yes) {
            Invoke-JigGitOrThrow -GitExe $GitExe -Description "Could not create the git repository in $projectDir" `
                -GitArgs @('-C', $projectDir, 'init', '-b', 'main') | Out-Null
            $repoCreatedThisRun = $true
            $isRepo = $true
        }
    }
    if (-not $isRepo) {
        Write-JigResult 'skipped: jig needs a git repository'
        return $null
    }

    # Q3: git identity, only if not already set (never overwritten). A
    # missing identity is expected and not an error, so these two reads go
    # straight through Invoke-JigNative rather than Invoke-JigGitOrThrow.
    $nameResult = Invoke-JigNative -FilePath $GitExe -NativeArgs @('-C', $projectDir, 'config', '--get', 'user.name')
    $emailResult = Invoke-JigNative -FilePath $GitExe -NativeArgs @('-C', $projectDir, 'config', '--get', 'user.email')
    $name = ($nameResult.Output -join "`n").Trim()
    $email = ($emailResult.Output -join "`n").Trim()
    if (-not $name) {
        if ($GitName) { $name = $GitName }
        elseif ($Yes) { $name = $env:USERNAME }
        else { $name = Read-JigValue -Prompt 'Git user.name' -Default $env:USERNAME }
        if ($name) {
            Invoke-JigGitOrThrow -GitExe $GitExe -Description 'Could not set your global git user.name' `
                -GitArgs @('config', '--global', 'user.name', $name) | Out-Null
        }
    }
    if (-not $email) {
        if ($GitEmail) { $email = $GitEmail }
        elseif ($Yes) { $email = "$env:USERNAME@example.com" }
        else { $email = Read-JigValue -Prompt 'Git user.email' -Default "$env:USERNAME@example.com" }
        if ($email) {
            Invoke-JigGitOrThrow -GitExe $GitExe -Description 'Could not set your global git user.email' `
                -GitArgs @('config', '--global', 'user.email', $email) | Out-Null
        }
    }

    # Q4: set up jig.
    Write-Host ''
    if (-not (Read-JigConfirm -Prompt 'Set up jig in this folder?' -Yes $Yes)) {
        return $projectDir
    }
    $initResult = Invoke-JigCommand -BashExe $BashExe -JigScriptPath $JigScriptPath `
        -WorkingDirectory $projectDir -JigArgs @('init', '--session-hook')
    $initResult.Output | ForEach-Object { Write-Host $_ }
    if ($initResult.ExitCode -ne 0) {
        throw "jig init failed in $projectDir"
    }

    # First commit, only when this run created the repository (never into
    # an existing one -- design.md D2: the installer never commits into a
    # repository it did not create).
    if ($repoCreatedThisRun) {
        if ($preExisting.Count -gt 0) {
            Write-Host "$($preExisting.Count) existing file(s) will be included in the first commit:"
            $preExisting | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" }
        }
        Invoke-JigGitOrThrow -GitExe $GitExe -Description "Could not stage files in $projectDir" `
            -GitArgs @('-C', $projectDir, 'add', '-A') | Out-Null

        # Executable bits git on Windows cannot record from the filesystem
        # (core.fileMode is false there): set them explicitly in the index
        # for jig's own entry points (D8/REQ-15), so macOS/Linux
        # collaborators who clone this repository do not inherit 100644.
        $execPaths = [System.Collections.Generic.List[string]]::new()
        $execPaths.Add('.ai/scripts/jig')
        $execPaths.Add('.ai/scripts/jig-session-hook')
        $profilesDir = Join-Path $projectDir '.ai\profiles'
        if (Test-Path -LiteralPath $profilesDir) {
            Get-ChildItem -LiteralPath $profilesDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                if (Test-Path -LiteralPath (Join-Path $_.FullName 'verify.sh')) {
                    $execPaths.Add(".ai/profiles/$($_.Name)/verify.sh")
                }
            }
        }
        foreach ($p in $execPaths) {
            if (Test-Path -LiteralPath (Join-Path $projectDir $p)) {
                Invoke-JigGitOrThrow -GitExe $GitExe -Description "Could not mark $p executable in $projectDir" `
                    -GitArgs @('-C', $projectDir, 'add', '--chmod=+x', '--', $p) | Out-Null
            }
        }
        Invoke-JigGitOrThrow -GitExe $GitExe -Description "Could not create the first commit in $projectDir" `
            -GitArgs @('-C', $projectDir, 'commit', '-q', '-m', 'Initial commit') | Out-Null
    }

    return $projectDir
}

# --- step 7: doctor -----------------------------------------------------------

function Invoke-JigDoctorCheck {
    param(
        [Parameter(Mandatory)][string]$BashExe,
        [Parameter(Mandatory)][string]$JigScriptPath,
        [string]$ProjectDir
    )
    $result = Invoke-JigCommand -BashExe $BashExe -JigScriptPath $JigScriptPath `
        -WorkingDirectory $ProjectDir -JigArgs @('doctor')
    $result.Output | ForEach-Object { Write-Host $_ }
}

# --- -Uninstall ----------------------------------------------------------------

# Uninstall-JigFramework -- the exact reverse of a default install.sh run
# (install.ps1 never passes --install-dir/--bin-dir, so these are always
# the two places to look). Removes the User PATH entry unconditionally (a
# PATH edit is always reversible); removes ~/.local/bin/jig only when it is
# actually a link into the checkout below; removes the checkout itself only
# when it still looks like an untouched jig source root with a clean `git
# status` (RULES.md: the installer never deletes what it did not create or
# verify is still exactly what it created). Git for Windows is never touched
# here (REQ-21: it serves more than jig).
function Uninstall-JigFramework {
    param([string]$GitExe)

    $installDir = Join-Path $env:USERPROFILE '.local\share\jig'
    $binDir = Join-Path $env:USERPROFILE '.local\bin'
    $scriptsDir = Join-Path $installDir 'scripts'
    $binJig = Join-Path $binDir 'jig'

    foreach ($dir in @($scriptsDir, $binDir)) {
        $current = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (Test-JigPathHasEntry -PathValue $current -Entry $dir) {
            $kept = @($current -split ';' | Where-Object {
                $_ -and ($_.TrimEnd('\', '/') -ne $dir.TrimEnd('\', '/'))
            })
            [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
            Write-JigResult "removed from PATH: $dir"
        }
    }

    if (Test-Path -LiteralPath $binJig) {
        $item = Get-Item -LiteralPath $binJig -Force -ErrorAction SilentlyContinue
        $target = $null
        if ($item -and $item.LinkType) {
            $target = $item.Target
            if ($target -is [System.Array]) { $target = $target[0] }
        }
        $targetsCheckout = $false
        if ($target) {
            $resolved = $target
            if (-not [System.IO.Path]::IsPathRooted($resolved)) {
                $resolved = Join-Path $binDir $resolved
            }
            $resolved = [System.IO.Path]::GetFullPath($resolved)
            $expected = [System.IO.Path]::GetFullPath((Join-Path $scriptsDir 'jig'))
            $targetsCheckout = ($resolved -ieq $expected)
        }
        if ($targetsCheckout) {
            Remove-Item -Force -LiteralPath $binJig
            Write-JigResult "removed: $binJig"
        }
        else {
            Write-JigResult "left in place (not a link into $installDir): $binJig"
        }
    }

    if (-not (Test-Path -LiteralPath $installDir)) {
        Write-JigResult "nothing installed at $installDir"
        return
    }

    $isSourceRoot = (
        (Test-Path -LiteralPath (Join-Path $installDir 'scripts\jig')) -and
        (Test-Path -LiteralPath (Join-Path $installDir 'skills')) -and
        (Test-Path -LiteralPath (Join-Path $installDir 'templates'))
    )
    if (-not $isSourceRoot) {
        Write-JigResult "refusing to remove ${installDir}: not a jig checkout"
        return
    }
    if (-not $GitExe) {
        Write-JigResult "refusing to remove ${installDir}: git is not available to verify it is unmodified"
        return
    }
    $statusResult = Invoke-JigNative -FilePath $GitExe -NativeArgs @('-C', $installDir, 'status', '--porcelain')
    if ($statusResult.ExitCode -ne 0 -or $statusResult.Output.Count -gt 0) {
        Write-JigResult "refusing to remove ${installDir}: it has local changes or is not a git checkout"
        return
    }
    Remove-Item -Recurse -Force -LiteralPath $installDir
    Write-JigResult "removed: $installDir"
}

# --- the whole run -------------------------------------------------------------

function Install-Jig {
    [CmdletBinding()]
    param(
        [switch]$Yes,
        [string]$Project,
        [string]$GitName,
        [string]$GitEmail,
        [switch]$NoInit,
        [string]$Ref,
        [switch]$Uninstall,
        [string]$Repository,
        [string]$InstallSh,
        [switch]$NoGitInstall
    )

    # `-File install.ps1 ...` runs this from a real script file, so
    # $PSCommandPath is set and calling `exit` at the end is safe -- the
    # process is expected to end anyway (this is how tests/install.t.ps1's
    # child-process scenarios read an exit code). `irm ... | iex` has no
    # backing file, so $PSCommandPath is empty; `exit` there would close the
    # user's whole PowerShell window over what should just be a red error
    # message, which is worse than the failure itself for someone who
    # abandons at the first incomprehensible error (spec.md's user).
    #
    # $env:JIG_INSTALL_NO_MAIN also disables `exit` here, on top of stopping
    # the entry point below from calling this function at all: the same
    # variable, mirroring install.sh's own JIG_INSTALL_NO_MAIN, lets
    # tests/install.t.ps1 dot-source this file and then call Install-Jig
    # directly -- e.g. with Find-JigGitCommand overridden, to exercise the
    # REQ-7 failure path -- without an `exit` inside it tearing down the
    # whole test process over one scenario. $PSCommandPath alone cannot make
    # that distinction: tests/install.t.ps1 is itself a running script file,
    # so $PSCommandPath is just as non-empty when Install-Jig is called
    # in-process from inside it as when install.ps1 runs standalone.
    #
    # Either way $exitCode is computed the same; only whether `exit` is
    # actually called differs. When it is not, the caller reads the outcome
    # from this function's own return value instead.
    $ranAsFile = ([bool]$PSCommandPath) -and ($env:JIG_INSTALL_NO_MAIN -ne '1')
    $YesBool = [bool]$Yes
    $exitCode = 0

    # Older Windows PowerShell 5.1 hosts default to TLS 1.0, which GitHub's
    # servers reject; every download in this file needs 1.2 available.
    [System.Net.ServicePointManager]::SecurityProtocol = ([System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12)

    $logDir = Join-Path $env:LOCALAPPDATA 'jig'
    $logPath = Join-Path $logDir 'install.log'
    $transcribing = $false
    try {
        New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null
        Start-Transcript -Path $logPath -Append -ErrorAction Stop | Out-Null
        $transcribing = $true
    }
    catch {
        Write-Host "jig: could not open $logPath for logging; continuing without it" -ForegroundColor Yellow
    }

    try {
        Write-Host 'Jig installer for Windows'

        if ($Uninstall) {
            $gitExeForUninstall = Find-JigGitCommand
            Uninstall-JigFramework -GitExe $gitExeForUninstall | Out-Null
        }
        else {
            # Steps 1/2: Git.
            Write-JigStep 'Looking for Git for Windows...'
            $gitExe = Find-JigGitCommand
            if ($gitExe) {
                Write-JigResult "found: $gitExe"
            }
            else {
                Write-JigResult 'not found'
                if ($NoGitInstall) {
                    throw (Get-JigGitMissingMessage)
                }
                Install-JigGitForWindows | Out-Null
                $gitExe = Find-JigGitCommand
                if (-not $gitExe) {
                    throw (Get-JigGitMissingMessage)
                }
            }
            $gitBinDir = Split-Path -Parent $gitExe
            if (-not (Test-JigPathHasEntry -PathValue $env:Path -Entry $gitBinDir)) {
                $env:Path = "$env:Path;$gitBinDir"
            }

            # Step 3: session PATH.
            Write-JigStep 'Refreshing PATH for this session...'
            Update-JigSessionPath
            Write-JigResult 'done'

            # Step 4: bash.
            Write-JigStep 'Looking for Git Bash...'
            $bashExe = Find-JigBash -GitExe $gitExe
            if (-not $bashExe) {
                throw (Get-JigGitMissingMessage)
            }
            Write-JigResult "found: $bashExe"

            # Step 5: jig.
            Write-JigStep 'Installing jig...'
            $installShPath = Get-JigInstallScript -InstallSh $InstallSh
            $installResult = Install-JigFramework -BashExe $bashExe -InstallShPath $installShPath `
                -Ref $Ref -Repository $Repository
            Write-JigResult "jig installed: $($installResult.JigScript) ($($installResult.Ref))"

            # Step 6: the first project.
            $projectDir = $null
            if (-not $NoInit) {
                Write-JigStep 'Setting up your project...'
                $projectDir = Initialize-JigProject -Project $Project -Yes $YesBool `
                    -GitName $GitName -GitEmail $GitEmail -GitExe $gitExe -BashExe $bashExe `
                    -JigScriptPath $installResult.JigScript
            }

            # Step 7: doctor.
            Write-JigStep 'Checking your setup (jig doctor)...'
            Invoke-JigDoctorCheck -BashExe $bashExe -JigScriptPath $installResult.JigScript `
                -ProjectDir $projectDir | Out-Null

            Write-Host ''
            Write-Host 'Open this folder in Claude Code (or Codex) and say: "start a task: <what you want to build>".'
        }
    }
    catch {
        $message = $_.Exception.Message
        Write-Host ''
        Write-Host "jig install failed: $message" -ForegroundColor Red
        Write-Host "See $logPath for the full log, or run the same line again after fixing this." -ForegroundColor Red
        $exitCode = 1
    }
    finally {
        if ($transcribing) {
            try { Stop-Transcript | Out-Null } catch { }
        }
    }

    if ($ranAsFile) {
        exit $exitCode
    }
    return $exitCode
}

# --- entry point ---------------------------------------------------------------
#
# $args carries whatever PowerShell could not bind to a named parameter when
# this file is run as `-File install.ps1 -Yes ...` (there is no top-level
# param() block to claim them itself, by design -- see the header comment).
# Guarded with Test-Path rather than referenced bare: at the true top level
# of an interactive `iex`, $args is not itself defined, and splatting an
# undefined variable there must not turn a pasted one-liner into an error
# before Install-Jig even starts.
#
# $env:JIG_INSTALL_NO_MAIN mirrors install.sh's own guard of the same name:
# it lets a caller (tests/install.t.ps1) dot-source this whole file --
# defining every function, Install-Jig included -- without that dot-source
# itself running the installer. It is part of this same final statement,
# not a separate earlier check, for the same truncation-safety reason
# install.sh's guard is: a transfer cut short anywhere above this line has
# defined functions but called nothing.
$JigForwardedArgs = @()
if (Test-Path Variable:\args) {
    $JigForwardedArgs = $args
}
if ($env:JIG_INSTALL_NO_MAIN -ne '1') {
    Install-Jig @JigForwardedArgs
}
