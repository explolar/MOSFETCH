# INSAT Interactive Downloader
# Select satellite -> select products -> select directory -> select dates -> download
# Each product is saved into its own subfolder under the chosen base directory.

$scriptRoot = $PSScriptRoot

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "INSAT INTERACTIVE DOWNLOADER" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ===== CREDENTIALS (never hard-coded; env vars or prompt) =====

if (-not $env:MOSDAC_USER) {
    $env:MOSDAC_USER = Read-Host "MOSDAC username"
}
if (-not $env:MOSDAC_PASS) {
    $securePass = Read-Host "MOSDAC password" -AsSecureString
    $env:MOSDAC_PASS = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass))
}

# ===== VERIFY CREDENTIALS NOW (fail fast, before any menus) =====

Write-Host ""
Write-Host "Checking MOSDAC login..." -ForegroundColor Cyan

$checkScript = "from mosfetch.client import MosdacClient`n" +
               "import os, sys`n" +
               "try:`n" +
               "    MosdacClient(os.environ['MOSDAC_USER'], os.environ['MOSDAC_PASS']).get_token()`n" +
               "    print('AUTH_OK')`n" +
               "except Exception as e:`n" +
               "    print('AUTH_FAIL: ' + str(e))`n" +
               "    sys.exit(1)`n"

Push-Location $scriptRoot
$authResult = $checkScript | python -
$authExit = $LASTEXITCODE
Pop-Location

if ($authExit -ne 0 -or $authResult -notmatch "AUTH_OK") {
    Write-Host ""
    Write-Host "LOGIN FAILED: $authResult" -ForegroundColor Red
    Write-Host "Check your MOSDAC username/password and try again." -ForegroundColor Yellow
    Remove-Item Env:\MOSDAC_USER -ErrorAction SilentlyContinue
    Remove-Item Env:\MOSDAC_PASS -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "Login OK." -ForegroundColor Green

# ===== SATELLITE & PRODUCT DEFINITIONS =====

$satellites = @{
    "1" = @{
        "name" = "INSAT-3DS"
        "products" = @{
            "1" = @{"name" = "L1B Standard Products"; "id" = "3SIMG_L1B_STD"; "filter" = "L1B_STD"}
            "2" = @{"name" = "L2P Winds (AMV)"; "id" = "3SIMG_L2P_AMV"; "filter" = "L2P_AMV"}
            "3" = @{"name" = "L3B Sea Surface Temp (SST)"; "id" = "3SIMG_L3B_SST"; "filter" = "L3B_SST"}
            "4" = @{"name" = "L3B Land Surface Temp (LST)"; "id" = "3SIMG_L3B_LST"; "filter" = "L3B_LST"}
            "5" = @{"name" = "L3B Brightness Temperature (BRT)"; "id" = "3SIMG_L3B_BRT"; "filter" = "L3B_BRT"}
        }
    }
    "2" = @{
        "name" = "INSAT-3DR"
        "products" = @{
            "1" = @{"name" = "L1C-SGP Imager"; "id" = "3RIMG_L1C_SGP"; "filter" = "L1C_SGP"}
            "2" = @{"name" = "L2P Winds (AMV)"; "id" = "3RIMG_L2P_AMV"; "filter" = "L2P_AMV"}
            "3" = @{"name" = "L3B Sea Surface Temp (SST)"; "id" = "3RIMG_L3B_SST"; "filter" = "L3B_SST"}
        }
    }
    "3" = @{
        "name" = "INSAT-3D"
        "products" = @{
            "1" = @{"name" = "L1B Standard Products"; "id" = "3IMG_L1B_STD"; "filter" = "L1B_STD"}
            "2" = @{"name" = "L2P Winds"; "id" = "3IMG_L2P_AMV"; "filter" = "L2P_AMV"}
        }
    }
}

# ===== MENU 1: SELECT SATELLITE =====

Write-Host ""
Write-Host "Select Satellite:" -ForegroundColor Green
Write-Host "1. INSAT-3DS (Newest)"
Write-Host "2. INSAT-3DR"
Write-Host "3. INSAT-3D"
Write-Host "4. ALL (download from all 3 satellites)"
Write-Host ""
$satChoice = Read-Host "Enter choice (1-4)"

$selectedSatellites = @()
if ($satChoice -eq "4") {
    $selectedSatellites = "1", "2", "3"
} else {
    $selectedSatellites = $satChoice
}

# ===== MENU 2: SELECT PRODUCTS =====

$selectedProducts = @()

foreach ($sat in $selectedSatellites) {
    if ($satellites.ContainsKey($sat)) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host "INSAT-$($satellites[$sat].name) - Select Products:" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Yellow

        foreach ($prod in $satellites[$sat].products.GetEnumerator()) {
            Write-Host "$($prod.Key). $($prod.Value.name)"
        }

        Write-Host "A. ALL products for this satellite"
        Write-Host ""
        $prodChoice = Read-Host "Enter choice(s) - comma separated or A for all"

        if ($prodChoice -eq "A" -or $prodChoice -eq "a") {
            foreach ($prod in $satellites[$sat].products.GetEnumerator()) {
                $selectedProducts += @{
                    "satellite" = $sat
                    "name" = $prod.Value.name
                    "id" = $prod.Value.id
                    "filter" = $prod.Value.filter
                }
            }
        } else {
            $prodChoices = $prodChoice -split ","
            foreach ($choice in $prodChoices) {
                $choice = $choice.Trim()
                if ($satellites[$sat].products.ContainsKey($choice)) {
                    $selectedProducts += @{
                        "satellite" = $sat
                        "name" = $satellites[$sat].products[$choice].name
                        "id" = $satellites[$sat].products[$choice].id
                        "filter" = $satellites[$sat].products[$choice].filter
                    }
                }
            }
        }
    }
}

if ($selectedProducts.Count -eq 0) {
    Write-Host "No products selected. Exiting." -ForegroundColor Yellow
    exit 0
}

# ===== MENU 3: SELECT DOWNLOAD DIRECTORY =====

Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Select Download Directory:" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "1. D:\insat_data (default)"
Write-Host "2. C:\insat_data"
Write-Host "3. Custom path"
Write-Host ""
$dirChoice = Read-Host "Enter choice (1-3)"

$baseDir = ""
if ($dirChoice -eq "1") {
    $baseDir = "D:\insat_data"
} elseif ($dirChoice -eq "2") {
    $baseDir = "C:\insat_data"
} elseif ($dirChoice -eq "3") {
    $baseDir = Read-Host "Enter custom directory path"
} else {
    $baseDir = "D:\insat_data"
}

# ===== MENU 4: SELECT DATE RANGE =====

Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Select Date Range:" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Yellow
$startDate = Read-Host "Start date (YYYY-MM-DD)"
$endDate = Read-Host "End date (YYYY-MM-DD)"

# ===== CONFIRMATION =====

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DOWNLOAD SUMMARY:" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Products to download: $($selectedProducts.Count)"
foreach ($prod in $selectedProducts) {
    Write-Host ("  - " + $prod.name + " (" + $prod.id + ")")
}
Write-Host ""
Write-Host "Base directory: $baseDir"
Write-Host "Each product will be in: $baseDir\<PRODUCT_ID>\"
Write-Host ""
Write-Host "Date range: $startDate to $endDate"
Write-Host ""
$confirm = Read-Host "Proceed? (Y/N)"

if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

# ===== CREATE FOLDERS & DOWNLOAD (parallel, one process per product) =====

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "STARTING DOWNLOADS..." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

$jobs = @()

foreach ($prod in $selectedProducts) {
    $productDir = Join-Path $baseDir $prod.id
    New-Item -ItemType Directory -Path $productDir -Force | Out-Null

    Write-Host "Starting download for: $($prod.name)" -ForegroundColor Yellow
    Write-Host "  Dataset ID: $($prod.id)"
    Write-Host "  Folder: $productDir"
    Write-Host ""

    $cmd = "Set-Location '$scriptRoot'; " +
           "`$env:MOSDAC_USER = '$($env:MOSDAC_USER)'; " +
           "`$env:MOSDAC_PASS = '$($env:MOSDAC_PASS)'; " +
           "python -m mosfetch --dataset-id $($prod.id) --name-filter $($prod.filter) --start $startDate --end $endDate --dest '$productDir'"

    $job = Start-Process powershell -ArgumentList "-NoProfile -Command `"$cmd`"" -NoNewWindow -PassThru

    $jobs += @{
        proc = $job
        name = $prod.name
        folder = $productDir
    }
}

Write-Host "All downloads started! Waiting for completion..." -ForegroundColor Cyan
Write-Host ""

foreach ($jobInfo in $jobs) {
    $jobInfo.proc | Wait-Process
    Write-Host ("Completed: " + $jobInfo.name) -ForegroundColor Green
}

# ===== SUMMARY =====

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "ALL DOWNLOADS COMPLETE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Files organized by product:" -ForegroundColor Cyan
foreach ($prod in $selectedProducts) {
    $productDir = Join-Path $baseDir $prod.id
    $fileCount = (Get-ChildItem $productDir -Filter "*.h5" -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Host ("  " + $prod.id + ": " + $fileCount + " files")
}
Write-Host ""
Write-Host "Base directory: $baseDir" -ForegroundColor Green

$openFolder = Read-Host "Open folder? (Y/N)"
if ($openFolder -eq "Y" -or $openFolder -eq "y") {
    explorer.exe $baseDir
}
