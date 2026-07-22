# Installs the cloudcosttree CLI on Windows: downloads the release binary
# matching your CPU from github.com/rulssss/cloudcosttree/releases into a
# folder you own (no Administrator prompt), and adds that folder to your
# User PATH if it isn't there already, so `cloudcosttree` works in a fresh
# terminal right after this finishes.
#
# Usage (PowerShell):
#
#   irm https://cloudcosttree.com/install.ps1 | iex
#
# Override the install directory by setting the env var first, in a
# separate line — not as `$env:X = ...; irm ... | iex` on one line, which
# works fine in PowerShell (unlike POSIX sh, PowerShell *does* share env
# vars across a `;`-separated pipeline in the same session) but is kept as
# two lines here for clarity:
#
#   $env:CLOUDCOSTTREE_INSTALL_DIR = "C:\tools\cloudcosttree"
#   irm https://cloudcosttree.com/install.ps1 | iex

$ErrorActionPreference = "Stop"

$repo = "rulssss/cloudcosttree"
$binName = "cloudcosttree.exe"

$installDir = $env:CLOUDCOSTTREE_INSTALL_DIR
if (-not $installDir) {
  $installDir = Join-Path $env:LOCALAPPDATA "cloudcosttree\bin"
}

$arch = $env:PROCESSOR_ARCHITECTURE
switch -Wildcard ($arch) {
  "AMD64" { $archName = "amd64" }
  "ARM64" { $archName = "arm64" }
  default {
    Write-Error "Unsupported architecture '$arch'. Download a binary manually from https://github.com/$repo/releases"
    exit 1
  }
}

$asset = "cloudcosttree-windows-$archName.exe"
$url = "https://github.com/$repo/releases/latest/download/$asset"

New-Item -ItemType Directory -Force -Path $installDir | Out-Null
$target = Join-Path $installDir $binName

Write-Host "Downloading $asset..."
Invoke-WebRequest -Uri $url -OutFile $target -UseBasicParsing

Write-Host "Installed cloudcosttree to $target"

# Add installDir to the current *User*'s PATH (no admin rights needed,
# unlike modifying the System PATH) if it isn't already there.
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -split ";" -notcontains $installDir) {
  $newPath = if ($userPath) { "$userPath;$installDir" } else { $installDir }
  [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
  Write-Host "Added $installDir to your User PATH."
  Write-Host ""
  Write-Host "Open a new terminal to use it, or run this to use it right now:"
  Write-Host "  `$env:Path = `"$installDir;`$env:Path`""
}

Write-Host ""
& $target --help | Select-Object -First 3
Write-Host ""
Write-Host "Done. Run 'cloudcosttree --help' to get started."
