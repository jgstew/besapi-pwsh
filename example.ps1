# Import the besapi module
try {
    $modulePath = Resolve-Path "./besapi.psm1" 
    Import-Module -Name $modulePath -Force
} catch {
    Write-Host "An error occurred:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
}
# Create a connection
$bes = Get-BESConnection -Username "User" -Password "Password" -RootServer "BigFix"

# Perform operations
Write-Host $bes.Get("help", @{})
Write-Host $bes.Get("sites", @{})
Write-Host $bes.Upload("./LICENSE", @{})
Write-Host $bes.SessionRelevanceXML("number of bes computers", @{})
