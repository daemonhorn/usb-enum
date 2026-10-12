# usb-enum

A PowerShell script that lists the USB devices currently present on a Windows machine and decodes their
vendor and product IDs (VID/PID) into human-readable names using the public [usb.ids](https://github.com/usbids/usbids) database.

## Features

- Enumerates present USB devices via `Get-PnpDevice`.
- Decodes VID/PID into vendor and product names.
- Caches `usb.ids` locally at `%LOCALAPPDATA%\usb-enum\usb.ids` (refreshed when older than 30 days).
- Smart filtering by friendly name, VID, PID, `VID:PID`, decoded vendor/product, or device class.

## Usage

```powershell
.\usb-enum.ps1 [--filter TEXT] [--refresh] [--max-cache-age DAYS] [--help]
```

| Option | Description |
|--------|-------------|
| `--filter TEXT` | Show only devices matching `TEXT` (case-insensitive substring). Space-separated words must all match, in any field. A leading `0x` is ignored. `--filter=TEXT` also works. |
| `--refresh` | Force a re-download of the `usb.ids` cache. |
| `--max-cache-age N` | Re-download the cache if older than `N` days (default 30). |
| `--help`, `-h`, `-?` | Show help. |

### Examples

```powershell
.\usb-enum.ps1 --filter yubi
.\usb-enum.ps1 --filter 1050:0407
.\usb-enum.ps1 --filter "logitech receiver" --refresh
```

Sample output:

```
FriendlyName         VendorID ProductID Vendor         Product           Status Class
------------         -------- --------- ------         -------           ------ -----
USB Composite Device 046D     C52B      Logitech, Inc. Unifying Receiver OK     USB
```

## Notes

- Requires PowerShell 5.1+ (tested on PowerShell 7) on Windows.
- `usb.ids` is downloaded from the GitHub mirror first, then `linux-usb.org` as a fallback.
- Devices not listed in `usb.ids` show a blank Vendor/Product.
- The script is distributed unsigned. If your execution policy requires signed scripts, sign it yourself with `Set-AuthenticodeSignature`.
