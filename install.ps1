$AppList = @(
    "AnyDesk.AnyDesk",
    "TeamViewer.TeamViewer.Host",
    "DucFabulous.UltraViewer",
    "Adobe.Acrobat.Reader.64-bit",
    "7zip.7zip",
    "Google.Chrome",
    "Mozilla.Firefox",
    "ChemTableSoftware.RegOrganizer",
    "Intel.IntelDriverAndSupportAssistant"
)

Write-Host "Starting Batch Deployment..." -ForegroundColor Green

foreach ($App in $AppList) {
    Write-Host "Deploying: $App" -ForegroundColor Cyan
    
    # Silent install and bypass all license agreements
    winget install --id $App --exact --accept-source-agreements --accept-package-agreements --silent
    
    # Check if the installation encountered an error
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[$App] Failed or already installed. Moving to next..." -ForegroundColor Yellow
    }
}

Write-Host "All deployment tasks completed!" -ForegroundColor Green
