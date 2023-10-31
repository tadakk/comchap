param(
    [string]$infile,
    [string]$outfile,
    [switch]$keepEdl,
    [switch]$keepMeta,
    [string]$ffmpegPath = "$PSScriptRoot\ffmpeg.exe",
    [string]$comskipPath = "PSScriptRoot\comskip.exe",
    [string]$comskipini = "$env:USERPROFILE\.comskip.ini",
    [string]$lockfile,
    [string]$workdir
)
if (-not $infile) {
    $exename = Split-Path -Leaf $PSCommandPath
    Write-Host "Add chapters to video file using EDL file"
    Write-Host "     (If no EDL file is found, comskip will be used to generate one)"
    Write-Host ""
    Write-Host "Usage: $exename infile [outfile]"
    exit 1
}
[bool]$deleteedl = !$keepEdl
[bool]$deletemeta = !$keepMeta
$deletelog = $true
$deletelogo = $true
$deletetxt = $true
$tempfiles = @()
$totalcutduration = 0
If ($lockfile) {
    if (Test-Path $lockfile) {
        Write-Host "lockfile: $lockfile"
        Write-Host "Waiting" -ForegroundColor Yellow
        while (Test-Path $lockfile) {
            sleep 5
            Write-Host "." -NoNewLine -ForegroundColor Yellow
        }
  }
  New-Item $lockfile
}
if (-not $outfile) {
    $outfile = $infile
}
$outdir = Split-Path $outfile -Parent
$outextension = ".$($outfile.Split(".")[-1])"
$comskipoutput = ""
if ($workdir) {
    if (!($workdir.EndsWith("\"))) {
       $workdir += "\"
    }
    $comskipoutput = "$workdir"
    $infileb = Split-Path $infile -Leaf
    $edlfile = "${workdir}$($infileb -replace '\.[^.]+$').edl"
    $metafile = "${workdir}$($infileb -replace '\.[^.]+$').ffmeta"
    $logfile = "${workdir}$($infileb -replace '\.[^.]+$').log"
    $logofile = "${workdir}$($infileb -replace '\.[^.]+$').logo.txt"
    $txtfile = "${workdir}$($infileb -replace '\.[^.]+$').txt"
}
else {
    $edlfile = "$($infile -replace '\.[^.]+$').edl"
    $metafile = "$($infile -replace '\.[^.]+$').ffmeta"
    $logfile = "$($infile -replace '\.[^.]+$').log"
    $logofile = "$($infile -replace '\.[^.]+$').logo.txt"
    $txtfile = "$($infile -replace '\.[^.]+$').txt"
}
if (-not (Test-Path $comskipIni)) {
    "output_edl=1" | Out-File -Encoding utf8 $comskipIni
}
elseif ((Get-Content $comskipIni) -notcontains "output_edl=1") {
    "output_edl=1" | Add-Content -Encoding utf8 $comskipIni
}
if (-not (Test-Path $edlfile)) {
    & "$comskipPath" $comskipoutput --ini="$comskipIni" "$infile"
}
$start = 0
$i = 0
$hascommercials = $false
$concat = ""
$lines = Get-Content $edlfile
foreach ($line in $lines) {
    $fields = $line -split "`t"
    $end = [float]$fields[0]
    $startnext = [float]$fields[1]
    if ([double]$end * 1000 -gt [double]$start * 1000) {
        $i++
        $hascommercials = $true
        Add-Content -Path $metafile ";FFMETADATA1"
        Add-Content -Path $metafile "[CHAPTER]"
        Add-Content -Path $metafile "TIMEBASE=1/1000"
        Add-Content -Path $metafile "START=$([int]($start * 1000))"
        Add-Content -Path $metafile "END=$([int]($end * 1000))"
        Add-Content -Path $metafile "title=Chapter $i"
        Add-Content -Path $metafile ";FFMETADATA1"
        Add-Content -Path $metafile "[CHAPTER]"
        Add-Content -Path $metafile "TIMEBASE=1/1000"
        Add-Content -Path $metafile "START=$([int]($end * 1000))"
        Add-Content -Path $metafile "END=$([int]($startnext * 1000))"
        Add-Content -Path $metafile "title=Commercials $i"
    }
    $start = $startnext
}
if ($hascommercials) {
    $i++
    $endstring = & $ffmpegPath -hide_banner -nostdin -i $infile 2>&1 | Select-String -Pattern "Duration" | ForEach-Object { $_ -replace '\D+(\d+:\d+:\d+.\d+),.*', '$1' }
    $end=([TimeSpan]::Parse($endstring)).TotalSeconds
    $i++
    Add-Content -Path $metafile "[CHAPTER]"
    Add-Content -Path $metafile "TIMEBASE=1/1000"
    Add-Content -Path $metafile "START=$([int]($start * 1000))"
    Add-Content -Path $metafile "END=$([int]($end * 1000))"
    Add-Content -Path $metafile "title=Chapter $i"
    If($infile -eq $outfile) {
        $tempfile="$outdir\$(New-Guid)$outextension" 
        echo "Writing file to temporary file: $tempfile"
        try {& $ffmpegPath -loglevel error -hide_banner -nostdin -i $infile -i $metafile -map_metadata 1 -codec copy -y $tempfile
            Move-Item $tempfile $outfile -Force -Confirm:$False
            echo "Saved to: $outfile"
        } catch { echo "Error running ffmpeg: $infile" }
    }
  else {
    try {& $ffmpegPath -hide_banner -loglevel error -nostdin -i $infile -i $metafile -c copy -map_metadata 1 -y $outfile}
    catch {Write-Host "Error running ffmpeg: $infile"}
    }
}
If (!(Test-Path $outfile)) {
    Write-Error "Error, $outfile does not exist."
    Exit 1
}
foreach ($tempfile in $tempfiles) {
    Remove-Item -Path $tempfile -ErrorAction SilentlyContinue
}
if ($deleteedl) {
     Remove-Item -Path $edlfile -ErrorAction SilentlyContinue
}
if ($deletemeta) {
     Remove-Item -Path $metafile -ErrorAction SilentlyContinue
}
if ($deletelog) {
     Remove-Item -Path $logfile -ErrorAction SilentlyContinue
}
if ($deletelogo) {
     Remove-Item -Path $logofile -ErrorAction SilentlyContinue
}
if ($deletetxt) {
     Remove-Item -Path $txtfile -ErrorAction SilentlyContinue
}
if ($ldPath) {
    $env:LD_LIBRARY_PATH = $ldPath
}
if ($lockfile) {
    Remove-Item -Path $lockfile -ErrorAction SilentlyContinue
}
