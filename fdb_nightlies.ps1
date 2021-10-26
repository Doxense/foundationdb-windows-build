param(
    [Parameter(Mandatory = $true)][string]$RunId,
    [Parameter(Mandatory = $true)][string]$SlackPath   
)

class PullRequest{
    [string]$Id
    [string]$Title
}

function LogTime {
    $(Get-Date -Format "HH:mm:ss")
}

function TraceLine {
    param(
        [Parameter(Mandatory = $true)][string]$Line
    )
    Write-Output "$(LogTime) $Line"  >> $LogFile
}
    
function Run {
    param(
        [Parameter(Mandatory = $true)][string]$Command
    )
    
    TraceLine -Line "Runnning command: $Command"
    Invoke-Expression -Command "$Command" 2>&1 | Out-File -Append -FilePath $LogFile
    if($LASTEXITCODE -ne 0){
        TraceLine "Command failed with code: $LASTEXITCODE"
        $global:SubcommandFailed = $true
        throw "Command failed with code: $LASTEXITCODE"
    }
}
    
function RunPS {
    param(
        [Parameter(Mandatory = $true)][string]$Command
    )
    
    TraceLine -Line "Runnning command: $Command"
    Invoke-Expression -Command "$Command 2>&1 | Out-File -Append -FilePath $LogFile"
    if(!$?){
        TraceLine "PS Command failed"
        $global:SubcommandFailed = $true
        throw "PS Command failed"
    }
}

function BuildMainBranch{
    param(
        [Parameter(Mandatory = $true)][string]$Branch
    )
    RunPS -Command "Set-Location $BuildDir"
    RunPS -Command "Remove-Item "".\foundationdb"" -Recurse -Force -Confirm:`$false -ErrorAction Ignore"
    Run -Command "git clone https://github.com/apple/foundationdb/"
    $LogFileName = "fdb-windows-build.$Branch.$(Get-Date -Format "yyyy-MM-dd").log"
    RunPS -Command "Set-Location $SourceDir"
    Run -Command "git switch $Branch"
    Run -Command "git pull"
    $CommitId = git log --format="%H" -n 1
    $SubCommitId = $CommitId.Substring(0,6)
    TraceLine -Line "Commit id: $CommitId"
    $global:BranchLogFile = "$global:LogDir\$LogFileName"
    try{
        Build
        $global:MainSlackText = "$global:MainSlackText\u2714   $Branch (``<$CommitPath/$CommitId|$SubCommitId>``):   *SUCCEEDED*\n"
    }
    catch{
        $global:MainSlackText = "$global:MainSlackText\u274C   $Branch (``<$CommitPath/$CommitId|$SubCommitId>``):   *FAILED*\n"
    }
    $global:LogFile = $global:MainLogFile
}

function BuildPRs{
    param(
        [Parameter(Mandatory = $true)][PullRequest]$PR
    )

    RunPS -Command "Set-Location $BuildDir"
    RunPS -Command "Remove-Item $SourceDir -Recurse -Force -Confirm:`$false -ErrorAction Ignore"
    $LogFileName = "fdb-windows-build.pr$($PR.Id).$(Get-Date -Format "yyyy-MM-dd").log"
    Run -Command "git clone $FDBRepos"
    RunPS -Command "Set-Location $SourceDir"
    try{
        Run -Command "gh pr checkout $($PR.Id)"
        Run -Command "git pull"
    }
    catch{
        TraceLine "Cannot checkout the pull request #$($PR.Id)"
        return
    }
    #gh pr checkout $PR.Id
    $CommitId = git log --format="%H" -n 1
    $SubCommitId = $CommitId.Substring(0,6)
    TraceLine -Line "Commit id: $CommitId"
    
    $global:BranchLogFile = "$global:LogDir\$LogFileName"
    try{
        Build
        $global:PRsSlackText = "$global:PRsSlackText\u2714   <$PRPath/$($PR.Id)|#$($PR.Id)> (``<$CommitPath/$CommitId|$SubCommitId>``): $($PR.Title)\n"
    }
    catch{
        $global:PRsSlackText = "$global:PRsSlackText\u274C   <$PRPath/$($PR.Id)|#$($PR.Id)> (``<$CommitPath/$CommitId|$SubCommitId>``): $($PR.Title)\n"
    }
    $global:LogFile = $global:MainLogFile
}

function Build{
    RunPS -Command "Remove-Item $SolutionDir -Recurse -Force -Confirm:`$false -ErrorAction Ignore"
    RunPS -Command "New-Item -ItemType ""directory"" -Path $SolutionDir -ErrorAction Ignore"
    RunPS -Command "Set-Location $SolutionDir"
    $global:LogFile = $global:BranchLogFile
    Run -Command "cmake -G ""Visual Studio 16 2019"" -A x64 -T ClangCL -DBOOST_ROOT=$BuildDir\boost_1_76_0 $SourceDir"
    Run -Command "msbuild /p:CL_MPCount=32 /p:UseMultiToolTask=true /p:Configuration=Release foundationdb.sln"
}

$global:BuildDir = Get-Location
$global:SourceDir = "$BuildDir\foundationdb"
$global:SolutionDir = "$BuildDir\build"
$global:LogDir = "$BuildDir\build_logs"
$global:FDBRepos = "https://github.com/apple/foundationdb/"
$global:CommitPath = "https://github.com/apple/foundationdb/commit"
$global:PRPath = "https://github.com/apple/foundationdb/pull"
$global:LogPath = "https://github.com/Doxense/foundationdb-windows-build/actions/runs/$RunId"
$global:MainLogFile = "$BuildDir\..\build_history\fdb-nightlies-build.$(Get-Date -Format "yyyy-MM-dd").log"
$global:BranchLogFile
$global:LogFile = $global:MainLogFile
$global:MainSlackText = ""
$global:PrsSLackText = ""
$global:SubcommandFailed

# Prepare build environment
New-Item -ItemType "directory" -Path $BuildDir\..\build_history -ErrorAction Ignore
RunPS -Command "Set-Location $BuildDir"
RunPS -Command "Remove-Item $global:LogDir -Recurse -Force -Confirm:`$false -ErrorAction Ignore"
RunPS -Command "New-Item -ItemType ""directory"" -Path $global:LogDir -ErrorAction Ignore"

# Download boost
RunPS -Command "Set-Location $BuildDir"
RunPS -Command "Invoke-WebRequest ""https://boostorg.jfrog.io/ui/api/v1/download?repoKey=main&path=release%252F1.76.0%252Fsource%252Fboost_1_76_0.7z"" -OutFile $BuildDir\boost_1_76_0.7z"
If ((Get-FileHash $BuildDir\boost_1_76_0.7z).Hash -ne "88782714F8701B6965F3FCE087A66A1262601DD5CCD5B2E5305021BEB53042A1") {
    Write-Output "boost hash does not match the expected value!"
    exit 1
}
Run -Command "7z x -y $BuildDir\boost_1_76_0.7z"

# Build main branches
BuildMainBranch -Branch master
BuildMainBranch -Branch release-7.0
BuildMainBranch -Branch release-6.3

# Build pull requests
RunPS -Command "Set-Location $global:BuildDir"
RunPS -Command "Remove-Item $global:SourceDir -Recurse -Force -Confirm:`$false -ErrorAction Ignore"
Run -Command "git clone $FDBRepos"
RunPS -Command "Set-Location $SourceDir"

$PullRequests = New-Object Collections.Generic.List[PullRequest]
$PRsList = (gh pr list -s open --limit 1000)
foreach($PR in $PRsList){
    $SplittedPR = ConvertFrom-String $PR -Delimiter "`t"
    $PRObj = [PullRequest]::new()
    $PRObj.Id = $SplittedPR.P1
    $PRObj.Title = $SplittedPR.P2
    if($PRObj.Title.Length -gt 36){
        $Subtitle = $PRObj.Title.Substring(0, 32).Trim()
        $PRObj.Title = "$Subtitle ..."
    }
    $PullRequests.Add($PRObj)
}

$RecentPRs = New-Object Collections.Generic.List[PullRequest]
foreach($PR in $PullRequests) {
    Run -Command "gh pr checkout $($PR.Id)"
    $LastModified = git log -1 --format=%cd --date=format:%Y-%m-%dT%H:%M:%S
    $CurrentTime = (Get-Date).ToString("yyyy-MM-ddThh:mm:ss")
    if((New-TimeSpan -Start $LastModified -End $CurrentTime).Days -eq 0){
        $RecentPRs.Add($PR)
    }
}
TraceLine -Line "Building the folowing pull requests"
foreach($PR in $RecentPRs){
    TraceLine -Line "$($PR.Id): $($PR.Title)"
}

foreach($PR in $RecentPRs){
    BuildPRs $PR
}

if($global:PRsSlackText.Length -eq 0){
    $global:PRsSlackText = "\u2714   No new pull request to build"
}

$SlackMessageTemplate = "$BuildDir\sources\skack_message_template.json"
$SlackMessage = Get-Content $SlackMessageTemplate
$global:MainSlackText = $global:MainSlackText -replace "master", "master       "
$SlackMessage = $SlackMessage -replace "main-text", $global:MainSlackText
$SlackMessage = $SlackMessage -replace "pr-text", $global:PRsSlackText
$SlackMessage = $SlackMessage -replace "log-text", "Build logs available <$global:LogPath|here> for 90 days"
TraceLine -Line [string]$SlackMessage

# Post build results to Slack
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Content-Type", "application/json")
RunPS -Command "Invoke-RestMethod `$SlackPath -Method 'POST' -Headers `$headers -Body `$SlackMessage"
RunPS -Command "Set-Location ""$BuildDir"""

if($SubcommandFailed){
    Write-Output "Nightlies process completed, but one or several builds failed"
    exit 1
}