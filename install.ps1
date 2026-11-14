# Installs Tiffin on Windows 10/11 (x64 or ARM64) from the latest GitHub release.
#
#   irm https://raw.githubusercontent.com/<owner>/<repo>/main/scripts/install.ps1 | iex
#
# Environment:
#   TIFFIN_VERSION  install this release (x.y.z, no v) instead of the latest
#   TIFFIN_REPO     owner/name of the release repository (default helloashif/tiffin)
#
# Runs the signed per-user installer silently (no administrator needed) after
# checking it against the release's checksums.txt.
# macOS and Linux: use scripts/install.sh.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repo = if ($env:TIFFIN_REPO) { $env:TIFFIN_REPO } else { 'helloashif/tiffin' }
$base = "https://github.com/$repo/releases"

$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { 'amd64' }
    'ARM64' { 'arm64' }
    default { throw "unsupported architecture $($env:PROCESSOR_ARCHITECTURE)" }
}

$version = $env:TIFFIN_VERSION
if (-not $version) {
    $req = [System.Net.HttpWebRequest]::Create("$base/latest")
    $req.AllowAutoRedirect = $false
    $res = $req.GetResponse()
    $loc = $res.Headers['Location']
    $res.Close()
    if (-not $loc) { throw "cannot find the latest release at $base" }
    $version = ($loc -split '/')[-1]
}
$version = $version.TrimStart('v')
if ($version -notmatch '^\d+\.\d+\.\d+') { throw "no release found at $base (got '$version')" }
Write-Host "Installing Tiffin $version (windows/$arch)"

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("tiffin-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $file = "tiffin-$version-windows-$arch-setup.exe"
    $dl = "$base/download/v$version"
    Invoke-WebRequest "$dl/checksums.txt" -OutFile "$tmp\checksums.txt"
    Invoke-WebRequest "$dl/$file" -OutFile "$tmp\$file"

    $line = Get-Content "$tmp\checksums.txt" | Where-Object { $_ -match "\s\*?$([regex]::Escape($file))$" } | Select-Object -First 1
    if (-not $line) { throw "$file is not in checksums.txt" }
    $want = ($line -split '\s+')[0].ToLower()
    $got = (Get-FileHash "$tmp\$file" -Algorithm SHA256).Hash.ToLower()
    if ($want -ne $got) { throw "checksum mismatch for $file" }

    $sig = Get-AuthenticodeSignature "$tmp\$file"
    if ($sig.Status -ne 'Valid') { Write-Warning "the installer's signature is $($sig.Status)" }

    $p = Start-Process -FilePath "$tmp\$file" -ArgumentList '/S' -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "the installer exited with code $($p.ExitCode)" }
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Done. Open a new terminal, then:"
Write-Host "  tiffin elevate    # one-time system setup"
Write-Host "  tiffin doctor     # check everything works"
