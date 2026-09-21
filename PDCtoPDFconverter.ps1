# ============================================================
# Locklizard PDC -> PDF Memory Extraction
# ============================================================

$ErrorActionPreference = "Stop"

# ============================================================
# CONFIGURATION
# ============================================================

$pdcFile = "C:\Users\ajaykumar\Downloads\Amritha\paper.pdc"

$viewer = "C:\Program Files\Locklizard Safeguard PDF Viewer\PDCViewer64.exe"

$procdump = "C:\Users\ajaykumar\AppData\Local\Microsoft\WindowsApps\procdump.exe"


# ============================================================
# VALIDATE REQUIRED FILES
# ============================================================

Write-Host ""
Write-Host "=============================================="
Write-Host " Locklizard PDC -> PDF Extraction"
Write-Host "=============================================="
Write-Host ""

if (-not (Test-Path -LiteralPath $pdcFile)) {
    Write-Error "PDC file not found:`n$pdcFile"
    exit 1
}

if (-not (Test-Path -LiteralPath $viewer)) {
    Write-Error "Locklizard viewer not found:`n$viewer"
    exit 1
}

if (-not (Test-Path -LiteralPath $procdump)) {
    Write-Error "ProcDump not found:`n$procdump"
    exit 1
}


# ============================================================
# OUTPUT PATHS
# ============================================================

$pdcItem = Get-Item -LiteralPath $pdcFile

$directory = $pdcItem.DirectoryName

$baseName = [System.IO.Path]::GetFileNameWithoutExtension(
    $pdcItem.Name
)

$dumpFile = Join-Path `
    $directory `
    "$baseName.dmp"

$pdfFile = Join-Path `
    $directory `
    "$baseName.pdf"


# ============================================================
# DISPLAY CONFIGURATION
# ============================================================

Write-Host "[+] PDC File:"
Write-Host "    $pdcFile"

Write-Host ""
Write-Host "[+] Locklizard Viewer:"
Write-Host "    $viewer"

Write-Host ""
Write-Host "[+] ProcDump:"
Write-Host "    $procdump"

Write-Host ""
Write-Host "[+] Output PDF:"
Write-Host "    $pdfFile"

Write-Host ""


# ============================================================
# FUNCTION: FIND BYTE PATTERN
# ============================================================

function Find-BytePattern {

    param (
        [byte[]]$Data,
        [byte[]]$Pattern,
        [int]$StartIndex = 0
    )

    if ($Pattern.Length -eq 0) {
        return -1
    }

    for (
        $i = $StartIndex;
        $i -le ($Data.Length - $Pattern.Length);
        $i++
    ) {

        $match = $true

        for (
            $j = 0;
            $j -lt $Pattern.Length;
            $j++
        ) {

            if ($Data[$i + $j] -ne $Pattern[$j]) {
                $match = $false
                break
            }
        }

        if ($match) {
            return $i
        }
    }

    return -1
}


# ============================================================
# REMOVE PREVIOUS OUTPUT
# ============================================================

if (Test-Path -LiteralPath $dumpFile) {

    Write-Host "[+] Removing previous dump..."

    Remove-Item `
        -LiteralPath $dumpFile `
        -Force `
        -ErrorAction SilentlyContinue
}

if (Test-Path -LiteralPath $pdfFile) {

    Write-Host "[+] Removing previous PDF..."

    Remove-Item `
        -LiteralPath $pdfFile `
        -Force `
        -ErrorAction SilentlyContinue
}


# ============================================================
# START LOCKLIZARD
# ============================================================

Write-Host ""
Write-Host "=============================================="
Write-Host " Starting Locklizard"
Write-Host "=============================================="
Write-Host ""

$viewerProcess = Start-Process `
    -FilePath $viewer `
    -ArgumentList "`"$pdcFile`"" `
    -PassThru

Write-Host "[+] Viewer started."
Write-Host "[+] Initial PID: $($viewerProcess.Id)"


# ============================================================
# WAIT FOR PDC TO LOAD
# ============================================================

Write-Host ""
Write-Host "[+] Waiting 6 seconds for the PDC to load..."

Start-Sleep -Seconds 6


# ============================================================
# FIND PDCVIEWER64 PROCESS
# ============================================================

Write-Host ""
Write-Host "[+] Searching for PDCViewer64 process..."

$pdcProcesses = Get-Process `
    -Name "PDCViewer64" `
    -ErrorAction SilentlyContinue


if ($pdcProcesses) {

    $targetProcess = $pdcProcesses |
        Where-Object {
            $_.Id -eq $viewerProcess.Id
        } |
        Select-Object -First 1

    if (-not $targetProcess) {

        $targetProcess = $pdcProcesses |
            Sort-Object StartTime |
            Select-Object -Last 1
    }

    $targetPid = $targetProcess.Id
}

else {

    Write-Host "[!] Get-Process did not find PDCViewer64."
    Write-Host "[+] Trying CIM process detection..."

    $cimProcess = Get-CimInstance Win32_Process |
        Where-Object {
            $_.ExecutablePath -eq $viewer
        } |
        Select-Object -First 1

    if (-not $cimProcess) {
        Write-Error "Unable to locate PDCViewer64 process."
        exit 1
    }

    $targetPid = [int]$cimProcess.ProcessId
}


# ============================================================
# DISPLAY TARGET
# ============================================================

Write-Host ""
Write-Host "[+] Target process:"
Write-Host "    PDCViewer64"

Write-Host "[+] Target PID:"
Write-Host "    $targetPid"


# ============================================================
# CREATE FULL MEMORY DUMP
# ============================================================

Write-Host ""
Write-Host "=============================================="
Write-Host " Creating Memory Dump"
Write-Host "=============================================="
Write-Host ""

Write-Host "[+] Dump file:"
Write-Host "    $dumpFile"

Write-Host ""
Write-Host "[+] Running ProcDump..."
Write-Host ""

& $procdump `
    -accepteula `
    -ma `
    $targetPid `
    $dumpFile

$procDumpExitCode = $LASTEXITCODE


# ============================================================
# VERIFY DUMP
# ============================================================

if (-not (Test-Path -LiteralPath $dumpFile)) {

    Write-Error "ProcDump did not create the memory dump."

    Stop-Process `
        -Id $targetPid `
        -Force `
        -ErrorAction SilentlyContinue

    exit 1
}

$dumpInfo = Get-Item -LiteralPath $dumpFile

if ($dumpInfo.Length -le 0) {

    Write-Error "The memory dump is empty."

    Stop-Process `
        -Id $targetPid `
        -Force `
        -ErrorAction SilentlyContinue

    exit 1
}


Write-Host ""
Write-Host "[+] ProcDump completed."
Write-Host "[+] ProcDump exit code: $procDumpExitCode"
Write-Host "[+] Dump successfully created."
Write-Host "[+] Dump size: $($dumpInfo.Length) bytes"


# ============================================================
# TERMINATE LOCKLIZARD
# ============================================================

Write-Host ""
Write-Host "[+] Terminating PDCViewer64..."

Stop-Process `
    -Id $targetPid `
    -Force `
    -ErrorAction SilentlyContinue

Start-Sleep -Seconds 1


# ============================================================
# READ MEMORY DUMP
# ============================================================

Write-Host ""
Write-Host "=============================================="
Write-Host " Searching Memory Dump"
Write-Host "=============================================="
Write-Host ""

Write-Host "[+] Loading dump..."

$bytes = [System.IO.File]::ReadAllBytes(
    $dumpFile
)

Write-Host "[+] Dump loaded."
Write-Host "[+] Dump size: $($bytes.Length) bytes"


# ============================================================
# PDF SIGNATURES
# ============================================================

$pdfHeader = [System.Text.Encoding]::ASCII.GetBytes(
    "%PDF-1.7"
)

$pdfEOF = [System.Text.Encoding]::ASCII.GetBytes(
    "%%EOF"
)


# ============================================================
# FIND PDF HEADER
# ============================================================

Write-Host ""
Write-Host "[+] Searching for %PDF-1.7..."

$offset1 = Find-BytePattern `
    -Data $bytes `
    -Pattern $pdfHeader


if ($offset1 -lt 0) {

    Write-Error "Could not find %PDF-1.7 in the memory dump."

    Remove-Item `
        -LiteralPath $dumpFile `
        -Force `
        -ErrorAction SilentlyContinue

    exit 1
}


Write-Host ""
Write-Host "[+] PDF header found."
Write-Host "    Offset: $offset1"


# ============================================================
# FIND %%EOF
# ============================================================

Write-Host ""
Write-Host "[+] Searching for %%EOF..."

$offset2 = Find-BytePattern `
    -Data $bytes `
    -Pattern $pdfEOF `
    -StartIndex $offset1


if ($offset2 -lt 0) {

    Write-Error "Could not find %%EOF after the PDF header."

    Remove-Item `
        -LiteralPath $dumpFile `
        -Force `
        -ErrorAction SilentlyContinue

    exit 1
}


Write-Host ""
Write-Host "[+] %%EOF found."
Write-Host "    Offset: $offset2"


# ============================================================
# CALCULATE PDF SIZE
# ============================================================

$pdfLength = ($offset2 - $offset1) + 5

Write-Host ""
Write-Host "[+] PDF start offset:"
Write-Host "    $offset1"

Write-Host "[+] PDF end offset:"
Write-Host "    $($offset2 + 5)"

Write-Host "[+] PDF size:"
Write-Host "    $pdfLength bytes"


# ============================================================
# VALIDATE RANGE
# ============================================================

if ($pdfLength -le 0) {

    Write-Error "Invalid PDF length."

    Remove-Item `
        -LiteralPath $dumpFile `
        -Force `
        -ErrorAction SilentlyContinue

    exit 1
}

if (($offset1 + $pdfLength) -gt $bytes.Length) {

    Write-Error "PDF extraction range exceeds dump size."

    Remove-Item `
        -LiteralPath $dumpFile `
        -Force `
        -ErrorAction SilentlyContinue

    exit 1
}


# ============================================================
# EXTRACT PDF
# ============================================================

Write-Host ""
Write-Host "=============================================="
Write-Host " Extracting PDF"
Write-Host "=============================================="
Write-Host ""

$pdfBytes = New-Object byte[] $pdfLength

[System.Array]::Copy(
    $bytes,
    $offset1,
    $pdfBytes,
    0,
    $pdfLength
)


# ============================================================
# WRITE PDF
# ============================================================

Write-Host "[+] Writing PDF..."

[System.IO.File]::WriteAllBytes(
    $pdfFile,
    $pdfBytes
)


# ============================================================
# VERIFY PDF
# ============================================================

if (-not (Test-Path -LiteralPath $pdfFile)) {

    Write-Error "PDF file was not created."

    Remove-Item `
        -LiteralPath $dumpFile `
        -Force `
        -ErrorAction SilentlyContinue

    exit 1
}


$pdfInfo = Get-Item -LiteralPath $pdfFile


# ============================================================
# VERIFY PDF HEADER
# ============================================================

$verifyBytes = New-Object byte[] 8

$verifyStream = [System.IO.File]::OpenRead($pdfFile)

try {

    [void]$verifyStream.Read(
        $verifyBytes,
        0,
        8
    )

}
finally {

    $verifyStream.Dispose()
}


$pdfSignature = [System.Text.Encoding]::ASCII.GetString(
    $verifyBytes
)


if ($pdfSignature -eq "%PDF-1.7") {

    Write-Host ""
    Write-Host "[+] PDF signature verified:"
    Write-Host "    $pdfSignature"

}
else {

    Write-Warning "Unexpected PDF signature: $pdfSignature"
}


# ============================================================
# REMOVE MEMORY DUMP
# ============================================================

Write-Host ""
Write-Host "[+] Removing memory dump..."

Remove-Item `
    -LiteralPath $dumpFile `
    -Force


# ============================================================
# FINAL RESULT
# ============================================================

Write-Host ""
Write-Host "=============================================="
Write-Host " PDF EXTRACTION SUCCESSFUL"
Write-Host "=============================================="
Write-Host ""

Write-Host "PDC:"
Write-Host "    $pdcFile"

Write-Host ""
Write-Host "PDF:"
Write-Host "    $pdfFile"

Write-Host ""
Write-Host "PDF Size:"
Write-Host "    $($pdfInfo.Length) bytes"

Write-Host ""
Write-Host "Memory Dump:"
Write-Host "    Removed"

Write-Host ""
Write-Host "=============================================="
Write-Host " DONE"
Write-Host "=============================================="