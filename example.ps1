# Import the besapi module
try {
    $modulePath = Resolve-Path "./besapi.psm1"
    Import-Module -Name $modulePath
} catch {
    Write-Host "An error occurred:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
}
# Create a connection
$bes = New-BESConnection -Username "admin" -Password "password" -RootServer "10.0.7.70"

# Perform operations
$result = $bes.Get("sites")
$sites = $result.BesXml

Write-Host $sites

# Export site contents
$bes.ExportSiteContents("custom/Demo")
