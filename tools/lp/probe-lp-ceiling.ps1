# probe-lp-ceiling.ps1 - bisect the largest size fastbootd will grant a logical partition.
# NOT read-only: every successful probe commits that size to LP metadata (grow-only; fs data untouched).
# Run from the platform-tools directory while the device sits in fastbootd (TWRP -> Reboot -> Fastboot).
param(
    [string]$Part = "system",
    [long]$Lo = 4718592000,      # current committed size = known good lower bound
    [long]$Hi = 9876062208       # extent-capped bound AFTER deleting product+system_ext
)                                # (use 8383365120 if probing without the deletes)

$fb = Join-Path $PSScriptRoot "fastboot.exe"
if (-not (Test-Path $fb)) { $fb = ".\fastboot.exe" }
if (-not (Test-Path $fb)) { throw "fastboot.exe not found - run from the platform-tools directory" }

$dev = & $fb devices 2>&1 | Out-String
if ($dev -notmatch "fastboot") { throw "no device in fastboot mode (TWRP -> Reboot -> Fastboot)" }

$u = & $fb getvar is-userspace 2>&1 | Out-String
if ($u -notmatch "is-userspace:\s*yes") { throw "not fastbootd (is-userspace != yes) - refusing" }

$p = & $fb getvar "partition-size:$Part" 2>&1 | Out-String
if ($p -notmatch "partition-size:$Part\s*:\s*0x") { throw "logical partition '$Part' not visible to fastbootd" }

Write-Host ("probing '{0}' between {1:N0} and {2:N0} bytes" -f $Part, $Lo, $Hi)
while ($Hi - $Lo -gt 1MB) {
    $mid = [long](($Lo + $Hi) / 2)
    $mid -= $mid % 1MB                              # keep probes 1 MiB aligned
    & $fb resize-logical-partition $Part $mid 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $Lo = $mid; Write-Host ("  OK      {0:N0}" -f $mid) }
    else                     { $Hi = $mid; Write-Host ("  refused {0:N0}" -f $mid) }
}

& $fb resize-logical-partition $Part $Lo 2>$null | Out-Null   # explicit: leave committed at the max
if ($LASTEXITCODE -ne 0) { throw "final commit at $Lo failed - metadata is at the last OK size above" }

$v = & $fb getvar "partition-size:$Part" 2>&1 | Out-String
Write-Host ("ceiling: {0:N0} bytes ({1:N2} GB)" -f $Lo, ($Lo / 1e9))
Write-Host ($v.Trim())
Write-Host "implied group maximum_size = ceiling + 1,762,811,904 (remaining members' bytes)"
