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
        # Full catalog per MOPD/PMPG/SIPA/T01/SEP-2024 (INSAT-3DS_Operational_Products_V1.pdf):
        # 35 Imager products + 5 special (*) + 4 Sounder products = 44 total.
        "products" = @{
            # ── Standard Products (L1B/L1C) ──
            "1"  = @{"name" = "L1B Standard Product (Full Disk)"; "id" = "3SIMG_L1B_STD"; "filter" = "L1B_STD"}
            "2"  = @{"name" = "L1C Sector Product (SGP)"; "id" = "3SIMG_L1C_SGP"; "filter" = "L1C_SGP"}
            "3"  = @{"name" = "L1C Sector Product (ASIA_MERCATOR)"; "id" = "3SIMG_L1C_ASIA_MER"; "filter" = "L1C_ASIA_MER"}
            # ── Geo-Physical L2B (from L1B) ──
            "4"  = @{"name" = "L2B Outgoing Longwave Radiation (OLR)"; "id" = "3SIMG_L2B_OLR"; "filter" = "L2B_OLR"}
            "5"  = @{"name" = "L2B Rainfall - Hydro Estimator (HEM)"; "id" = "3SIMG_L2B_HEM"; "filter" = "L2B_HEM"}
            "6"  = @{"name" = "L2B Upper Troposphere Humidity (UTH)"; "id" = "3SIMG_L2B_UTH"; "filter" = "L2B_UTH"}
            "7"  = @{"name" = "L2B Cloud Mask (CMK)"; "id" = "3SIMG_L2B_CMK"; "filter" = "L2B_CMK"}
            "8"  = @{"name" = "L2B Sea Surface Temp (SST)"; "id" = "3SIMG_L2B_SST"; "filter" = "L2B_SST"}
            "9"  = @{"name" = "L2B Land Surface Temp (LST)"; "id" = "3SIMG_L2B_LST"; "filter" = "L2B_LST"}
            "10" = @{"name" = "L2B Cloud Top Properties (CTP)"; "id" = "3SIMG_L2B_CTP"; "filter" = "L2B_CTP"}
            "11" = @{"name" = "L2B IMSRA Corrected Rainfall (IMC)"; "id" = "3SIMG_L2B_IMC"; "filter" = "L2B_IMC"}
            "12" = @{"name" = "L2B Total Precipitable Water Vapour (TPW)"; "id" = "3SIMG_L2B_TPW"; "filter" = "L2B_TPW"}
            # ── Geo-Physical L2C (from L1C) ──
            "13" = @{"name" = "L2C Fog"; "id" = "3SIMG_L2C_FOG"; "filter" = "L2C_FOG"}
            "14" = @{"name" = "L2C Snow (SNW)"; "id" = "3SIMG_L2C_SNW"; "filter" = "L2C_SNW"}
            "15" = @{"name" = "L2C Insolation (INS/DHI/DNI/GHI)"; "id" = "3SIMG_L2C_INS"; "filter" = "L2C_INS"}
            "16" = @{"name" = "L2C Day Cloud Microphysics (CMP)"; "id" = "3SIMG_L2C_CMP"; "filter" = "L2C_CMP"}
            "17" = @{"name" = "L2C Land Surface Albedo (LSA) *"; "id" = "3SIMG_L2C_LSA"; "filter" = "L2C_LSA"}
            "18" = @{"name" = "L2C Net Radiation (NER) *"; "id" = "3SIMG_L2C_NER"; "filter" = "L2C_NER"}
            "19" = @{"name" = "L2C Storm Index (STORM) *"; "id" = "3SIMG_L2C_STORM"; "filter" = "L2C_STORM"}
            # ── Geo-Physical L2P (Point) ──
            "20" = @{"name" = "L2P Fire (FIR, KML)"; "id" = "3SIMG_L2P_FIR"; "filter" = "L2P_FIR"}
            "21" = @{"name" = "L2P Smoke (SMK, KML)"; "id" = "3SIMG_L2P_SMK"; "filter" = "L2P_SMK"}
            "22" = @{"name" = "L2P Winds (AMV)"; "id" = "3SIMG_L2P_AMV"; "filter" = "L2P_AMV"}
            # ── Geo-Physical L2G (Gridded) ──
            "23" = @{"name" = "L2G Aerosol Optical Depth (AOD)"; "id" = "3SIMG_L2G_AOD"; "filter" = "L2G_AOD"}
            "24" = @{"name" = "L2G IMSRA Rainfall (IMR)"; "id" = "3SIMG_L2G_IMR"; "filter" = "L2G_IMR"}
            "25" = @{"name" = "L2G GOES Precip Index (GPI)"; "id" = "3SIMG_L2G_GPI"; "filter" = "L2G_GPI"}
            "26" = @{"name" = "L2G Wind Derived Products (WDP)"; "id" = "3SIMG_L2G_WDP"; "filter" = "L2G_WDP"}
            # ── Binned L3B (Daily) ──
            "27" = @{"name" = "L3B Outgoing Longwave Radiation (OLR)"; "id" = "3SIMG_L3B_OLR"; "filter" = "L3B_OLR"}
            "28" = @{"name" = "L3B Rainfall - Hydro Estimator (HEM)"; "id" = "3SIMG_L3B_HEM"; "filter" = "L3B_HEM"}
            "29" = @{"name" = "L3B Upper Troposphere Humidity (UTH)"; "id" = "3SIMG_L3B_UTH"; "filter" = "L3B_UTH"}
            "30" = @{"name" = "L3B Sea Surface Temp (SST)"; "id" = "3SIMG_L3B_SST"; "filter" = "L3B_SST"}
            "31" = @{"name" = "L3B Land Surface Temp (LST)"; "id" = "3SIMG_L3B_LST"; "filter" = "L3B_LST"}
            "32" = @{"name" = "L3B IMSRA Rainfall (IMC)"; "id" = "3SIMG_L3B_IMC"; "filter" = "L3B_IMC"}
            "33" = @{"name" = "L3B Short Wave Radiation over Ocean (SWR)"; "id" = "3SIMG_L3B_SWR"; "filter" = "L3B_SWR"}
            "34" = @{"name" = "L3B Brightness Temperature (BRT)"; "id" = "3SIMG_L3B_BRT"; "filter" = "L3B_BRT"}
            # ── Binned L3C (Daily) ──
            "35" = @{"name" = "L3C Insolation (INS/DHI/DNI/GHI)"; "id" = "3SIMG_L3C_INS"; "filter" = "L3C_INS"}
            "36" = @{"name" = "L3C Potential Evapotranspiration (PET)"; "id" = "3SIMG_L3C_PET"; "filter" = "L3C_PET"}
            "37" = @{"name" = "L3C Actual Evapotranspiration (AET) *"; "id" = "3SIMG_L3C_AET"; "filter" = "L3C_AET"}
            "38" = @{"name" = "L3C Land Surface Albedo (LSA) *"; "id" = "3SIMG_L3C_LSA"; "filter" = "L3C_LSA"}
            # ── Binned L3G (Daily) ──
            "39" = @{"name" = "L3G IMSRA Rainfall (IMR)"; "id" = "3SIMG_L3G_IMR"; "filter" = "L3G_IMR"}
            "40" = @{"name" = "L3G GOES Precip Index (GPI)"; "id" = "3SIMG_L3G_GPI"; "filter" = "L3G_GPI"}
            # ── Sounder Products ──
            "41" = @{"name" = "Sounder L1B Standard (India Region, SA1)"; "id" = "3SSND_L1B_SA1"; "filter" = "L1B_SA1"}
            "42" = @{"name" = "Sounder L1B Standard (Indian Ocean, SB1)"; "id" = "3SSND_L1B_SB1"; "filter" = "L1B_SB1"}
            "43" = @{"name" = "Sounder L2B Profiles (India Region, SA1)"; "id" = "3SSND_L2B_SA1"; "filter" = "L2B_SA1"}
            "44" = @{"name" = "Sounder L2B Profiles (Indian Ocean, SB1)"; "id" = "3SSND_L2B_SB1"; "filter" = "L2B_SB1"}
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

        $sortedProducts = $satellites[$sat].products.GetEnumerator() | Sort-Object { [int]$_.Key }
        foreach ($prod in $sortedProducts) {
            Write-Host "$($prod.Key). $($prod.Value.name)"
        }

        Write-Host "A. ALL products for this satellite"
        Write-Host ""
        $prodChoice = Read-Host "Enter choice(s) - comma separated or A for all"

        if ($prodChoice -eq "A" -or $prodChoice -eq "a") {
            foreach ($prod in $sortedProducts) {
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
$dirChoice = Read-Host "Enter choice (1-3, or type a path directly)"

$baseDir = ""
if ($dirChoice -eq "1") {
    $baseDir = "D:\insat_data"
} elseif ($dirChoice -eq "2") {
    $baseDir = "C:\insat_data"
} elseif ($dirChoice -eq "3") {
    $baseDir = Read-Host "Enter custom directory path"
} elseif ($dirChoice.Trim() -ne "") {
    # not 1/2/3 but not empty either -- treat it as a path typed directly,
    # rather than silently falling back to the default (D:\insat_data).
    $baseDir = $dirChoice.Trim()
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

# ===== CREATE FOLDERS & DOWNLOAD (one product at a time, to stay within MOSDAC's rate limits) =====

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "STARTING DOWNLOADS..." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

foreach ($prod in $selectedProducts) {
    $productDir = Join-Path $baseDir $prod.id
    New-Item -ItemType Directory -Path $productDir -Force | Out-Null

    Write-Host "Downloading: $($prod.name)" -ForegroundColor Yellow
    Write-Host "  Dataset ID: $($prod.id)"
    Write-Host "  Folder: $productDir"
    Write-Host ""

    $cmd = "Set-Location '$scriptRoot'; " +
           "`$env:MOSDAC_USER = '$($env:MOSDAC_USER)'; " +
           "`$env:MOSDAC_PASS = '$($env:MOSDAC_PASS)'; " +
           "python -m mosfetch --dataset-id $($prod.id) --name-filter $($prod.filter) --start $startDate --end $endDate --dest '$productDir'"

    Start-Process powershell -ArgumentList "-NoProfile -Command `"$cmd`"" -NoNewWindow -Wait

    Write-Host ("Completed: " + $prod.name) -ForegroundColor Green
    Write-Host ""
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
