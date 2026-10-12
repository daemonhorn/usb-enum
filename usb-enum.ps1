# Options are parsed by hand from $args so GNU-style --long options work.
$MaxCacheAgeDays = 30
$RefreshCache    = $false
$Filter          = $null

function Show-Help {
    @'
usb-enum.ps1 - list present USB devices with decoded vendor/product names

USAGE
    usb-enum.ps1 [--filter TEXT] [--refresh] [--max-cache-age DAYS] [--help]

OPTIONS
    --filter TEXT        Show only devices matching TEXT (case-insensitive substring).
                         Matches friendly name, VID, PID, "VID:PID", decoded vendor,
                         decoded product, and device class. Whitespace-separated
                         words must ALL match (in any field). A leading 0x is ignored.
                         Also accepted as --filter=TEXT.
    --refresh            Force re-download of the usb.ids cache.
    --max-cache-age N    Re-download cache if older than N days (default 30).
    --help, -h, -?       Show this help.

EXAMPLES
    usb-enum.ps1 --filter yubi
    usb-enum.ps1 --filter 1050:0407
    usb-enum.ps1 --filter "logitech receiver" --refresh

Cache: %LOCALAPPDATA%\usb-enum\usb.ids
'@
}

for ($i = 0; $i -lt $args.Count; $i++) {
    $a = [string]$args[$i]
    switch -regex ($a) {
        '^(--help|-h|-\?|/\?)$' { Show-Help; return }
        '^--refresh$'           { $RefreshCache = $true }
        '^--filter=(.*)$'       { $Filter = $Matches[1] }
        '^--filter$' {
            if (++$i -ge $args.Count) { Write-Error '--filter requires a value'; return }
            $Filter = [string]$args[$i]
        }
        '^--max-cache-age=(\d+)$' { $MaxCacheAgeDays = [int]$Matches[1] }
        '^--max-cache-age$' {
            if (++$i -ge $args.Count -or $args[$i] -notmatch '^\d+$') { Write-Error '--max-cache-age requires a number'; return }
            $MaxCacheAgeDays = [int]$args[$i]
        }
        default { Write-Error "Unknown option: $a (try --help)"; return }
    }
}

$CacheDir  = Join-Path $env:LOCALAPPDATA 'usb-enum'
$CacheFile = Join-Path $CacheDir 'usb.ids'
$Sources   = @(
    'https://raw.githubusercontent.com/usbids/usbids/master/usb.ids',
    'https://www.linux-usb.org/usb.ids'   # fallback; currently serves a mismatched sf.net certificate
)

function Update-UsbIdsCache {
    $stale = $RefreshCache -or -not (Test-Path $CacheFile) -or
             ((Get-Date) - (Get-Item $CacheFile).LastWriteTime).TotalDays -gt $MaxCacheAgeDays
    if (-not $stale) { return }

    New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
    foreach ($url in $Sources) {
        try {
            $tmp = "$CacheFile.tmp"
            Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            # Retry: AV/indexers can briefly hold the freshly written file open.
            for ($try = 1; ; $try++) {
                try { Copy-Item -Force $tmp $CacheFile -ErrorAction Stop; break }
                catch { if ($try -ge 5) { throw }; Start-Sleep -Milliseconds 500 }
            }
            Remove-Item $tmp -ErrorAction SilentlyContinue
            Write-Verbose "usb.ids cached from $url"
            return
        } catch {
            Write-Warning "Failed to fetch $url : $($_.Exception.Message)"
        }
    }
    if (-not (Test-Path $CacheFile)) {
        Write-Warning 'No usb.ids available; vendor/product names will be blank.'
    } else {
        Write-Warning 'Using stale usb.ids cache.'
    }
}

function Import-UsbIds {
    # Returns @{ Vendors = @{ 'vvvv' = name }; Products = @{ 'vvvv:pppp' = name } }
    $vendors  = @{}
    $products = @{}
    if (Test-Path $CacheFile) {
        $curVendor = $null
        foreach ($line in [System.IO.File]::ReadLines($CacheFile)) {
            if ($line.Length -eq 0 -or $line[0] -eq '#') { continue }
            if ($line -match '^([0-9a-f]{4})\s+(.+)$') {          # vendor
                $curVendor = $Matches[1]
                $vendors[$curVendor] = $Matches[2].Trim()
            } elseif ($line -match '^\t([0-9a-f]{4})\s+(.+)$') {  # product
                if ($curVendor) { $products["${curVendor}:$($Matches[1])"] = $Matches[2].Trim() }
            } elseif ($line -match '^\t\t') {                     # interface; ignore
                continue
            } else {                                              # class sections (C, AT, HID...) end the vendor list
                break
            }
        }
    }
    @{ Vendors = $vendors; Products = $products }
}

Update-UsbIdsCache
$ids = Import-UsbIds

$terms = @()
if ($Filter) {
    $terms = @(($Filter.Trim() -split '\s+') | Where-Object { $_ } | ForEach-Object { $_ -replace '^0x', '' })
}

Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match '^USB\\VID_' } | ForEach-Object {
    if ($_.InstanceId -match 'VID_(?<vid>[0-9A-F]{4})&PID_(?<pid>[0-9A-F]{4})') {
        $vendorId  = $Matches['vid'].ToLower()
        $productId = $Matches['pid'].ToLower()
        $dev = [PSCustomObject]@{
            FriendlyName = $_.FriendlyName
            VendorID     = $vendorId.ToUpper()
            ProductID    = $productId.ToUpper()
            Vendor       = $ids.Vendors[$vendorId]
            Product      = $ids.Products["${vendorId}:${productId}"]
            Status       = $_.Status
            Class        = $_.Class
        }
        if ($terms.Count) {
            $hay = @($dev.FriendlyName, $dev.VendorID, $dev.ProductID, "$($dev.VendorID):$($dev.ProductID)",
                     $dev.Vendor, $dev.Product, $dev.Class) -join "`n"
            foreach ($t in $terms) {
                if ($hay.IndexOf($t, [StringComparison]::OrdinalIgnoreCase) -lt 0) { return }
            }
        }
        $dev
    }
} | Format-Table -AutoSize
