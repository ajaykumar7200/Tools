$SourceFolder = "C:\Accurate Document"
$OutputFolder = "C:\Accurate Document\PDF"

# LibreOffice executable
$LibreOffice = "C:\Program Files\LibreOffice\program\soffice.exe"

if (!(Test-Path $LibreOffice)) {
    Write-Host "LibreOffice not found."
    exit
}

if (!(Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder | Out-Null
}

$files = Get-ChildItem $SourceFolder -Recurse -File |
Where-Object {
    $_.Extension -in ".doc",".docx"
}

$total = $files.Count
$count = 0

foreach($file in $files)
{
    $count++

    Write-Host "[$count/$total] $($file.Name)"

    Start-Process `
        -FilePath $LibreOffice `
        -ArgumentList "--headless --convert-to pdf --outdir `"$OutputFolder`" `"$($file.FullName)`"" `
        -Wait `
        -NoNewWindow
}

Write-Host ""
Write-Host "Completed!"