# Import the besapi module
try {
    $modulePath = Resolve-Path "./besapi.psm1" 
    Import-Module -Name $modulePath -Force
} catch {
    Write-Host "An error occurred:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
}


# Create a connection
# $bes = Get-BESConnection -Username "User" -Password "Password" -RootServer "BigFix"

# "~/.besapi.conf" is the default path for the python module config
$bes = Get-BESConnectionFromConfig -FilePath "~/.besapi.conf"

# Perform operations
Write-Host $bes.Get("help", @{})
Write-Host $bes.Get("sites", @{})
Write-Host $bes.Upload("./LICENSE.txt", @{})
Write-Host $bes.SessionRelevanceXML("number of bes computers", @{})
