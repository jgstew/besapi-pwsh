# besapi.psm1
# this is based upon a python module called besapi.py found here: 
#  - https://github.com/jgstew/besapi
# PowerShell module for communicating with the BES (BigFix) REST API
# This module provides functions and classes to interact with the BigFix REST API,
# including methods for authentication, sending requests, and handling responses.
# Requires -Version 7.5

# Import required modules
using namespace System.Net
using namespace System.Text
using namespace System.Xml
using namespace System.Xml.Linq
using namespace System.Collections.Generic
using namespace System.IO
using namespace System.Web

function Sanitize-Text {
    <#
    .SYNOPSIS
    Clean arbitrary text for safe file system usage.
    
    .DESCRIPTION
    Sanitizes strings to make them safe for file system operations.
    
    .PARAMETER Values
    One or more strings to sanitize.
    
    .EXAMPLE
    Sanitize-Text "file/name"
    #>
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$Values
    )
    
    begin {
        $validChars = '-_.() ' + [char[]][char]'A'..[char]'Z' + [char[]][char]'a'..[char]'z' + [char[]][char]'0'..[char]'9'
        $sanitizedValues = @()
    }
    
    process {
        foreach ($value in $Values) {
            $sanitized = $value.Replace("/", "-").Replace("\", "-")
            $result = ""
            foreach ($char in $sanitized.ToCharArray()) {
                if ($validChars -contains $char) {
                    $result += $char
                }
            }
            $sanitizedValues += $result
        }
    }
    
    end {
        return $sanitizedValues
    }
}

function Convert-XmlElementToHashtable {
    <#
    .SYNOPSIS
    Convert an XML element to a PowerShell hashtable.
    
    .DESCRIPTION
    Recursively converts XML elements to nested hashtables.
    
    .PARAMETER Node
    The XML node to convert.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlNode]$Node
    )
    
    $result = @{}
    
    foreach ($element in $Node.ChildNodes) {
        if ($element.NodeType -eq [System.Xml.XmlNodeType]::Element) {
            # Remove namespace prefix if present
            $key = $element.LocalName
            
            # Process element as text if it contains non-whitespace content
            if ($element.HasChildNodes -and $element.ChildNodes.Count -eq 1 -and $element.ChildNodes[0].NodeType -eq [System.Xml.XmlNodeType]::Text) {
                $value = $element.InnerText
            }
            else {
                $value = Convert-XmlElementToHashtable -Node $element
            }
            
            if ($result.ContainsKey($key)) {
                if ($result[$key] -is [array]) {
                    $result[$key] += $value
                }
                else {
                    $tempValue = $result[$key]
                    $result[$key] = @($tempValue, $value)
                }
            }
            else {
                $result[$key] = $value
            }
        }
    }
    
    return $result
}

class BESConnection {
    <#
    .SYNOPSIS
    BigFix REST API connection abstraction class
    #>
    
    [string]$Username
    [string]$RootServer
    [bool]$Verify
    [Microsoft.PowerShell.Commands.WebRequestSession]$Session
    [PSCredential]$Credential
    
    # Constructor
    BESConnection([string]$Username, [string]$Password, [string]$RootServer, [bool]$Verify = $false) {
        $this.Username = $Username
        $this.Verify = $Verify
        
        # Create a secure credential
        $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        $this.Credential = New-Object System.Management.Automation.PSCredential($Username, $securePassword)
        
        # Set up session
        $this.Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        
        # If not provided, add on https://
        if (-not $RootServer.StartsWith("http")) {
            $RootServer = "https://" + $RootServer
        }
        # If port not provided, add on the default :52311
        if (($RootServer.ToCharArray() | Where-Object { $_ -eq ':' } | Measure-Object).Count -ne 2) {
            $RootServer = $RootServer + ":52311"
        }
        
        $this.RootServer = $RootServer
        
        # No need to disable SSL warnings in modern PowerShell Core
        # PowerShell Core handles this with the -SkipCertificateCheck parameter
        
        $this.Login()
    }
    
    # Methods
    [string] Url([string]$Path) {
        if ($Path.StartsWith($this.RootServer)) {
            return $Path
        }
        else {
            return "$($this.RootServer)/api/$Path"
        }
    }
    
    [RESTResult] Get([string]$Path = "help", [hashtable]$Params = @{}) {
        $url = $this.Url($Path)
        
        $invokeParams = @{
            Uri = $url
            WebSession = $this.Session
            Method = 'Get'
            UseBasicParsing = $true
            Credential = $this.Credential
            Authentication = 'Basic'
            SkipCertificateCheck = (-not $this.Verify)
        }
        
        # Add any additional parameters
        foreach ($key in $Params.Keys) {
            $invokeParams[$key] = $Params[$key]
        }
        
        $response = Invoke-WebRequest @invokeParams
        return [RESTResult]::new($response)
    }
    
    [RESTResult] Post([string]$Path, [string]$Data, [hashtable]$Params = @{}) {
        $url = $this.Url($Path)
        
        $invokeParams = @{
            Uri = $url
            WebSession = $this.Session
            Method = 'Post'
            Body = $Data
            UseBasicParsing = $true
            Credential = $this.Credential
            Authentication = 'Basic'
            SkipCertificateCheck = (-not $this.Verify)
        }
        
        # Add any additional parameters
        foreach ($key in $Params.Keys) {
            $invokeParams[$key] = $Params[$key]
        }
        
        $response = Invoke-WebRequest @invokeParams
        return [RESTResult]::new($response)
    }
    
    [RESTResult] Put([string]$Path, [string]$Data, [hashtable]$Params = @{}) {
        $url = $this.Url($Path)
        
        $invokeParams = @{
            Uri = $url
            WebSession = $this.Session
            Method = 'Put'
            Body = $Data
            UseBasicParsing = $true
            Credential = $this.Credential
            Authentication = 'Basic'
            SkipCertificateCheck = (-not $this.Verify)
        }
        
        # Add any additional parameters
        foreach ($key in $Params.Keys) {
            $invokeParams[$key] = $Params[$key]
        }
        
        $response = Invoke-WebRequest @invokeParams
        return [RESTResult]::new($response)
    }
    
    [RESTResult] Delete([string]$Path, [hashtable]$Params = @{}) {
        $url = $this.Url($Path)
        
        $invokeParams = @{
            Uri = $url
            WebSession = $this.Session
            Method = 'Delete'
            UseBasicParsing = $true
            Credential = $this.Credential
            Authentication = 'Basic'
            SkipCertificateCheck = (-not $this.Verify)
        }
        
        # Add any additional parameters
        foreach ($key in $Params.Keys) {
            $invokeParams[$key] = $Params[$key]
        }
        
        $response = Invoke-WebRequest @invokeParams
        return [RESTResult]::new($response)
    }
    
    [RESTResult] SessionRelevanceXML([string]$Relevance, [hashtable]$Params = @{}) {
        # Use [System.Web.HttpUtility] if available, otherwise fall back to .NET method
        try {
            $encodedRelevance = [System.Web.HttpUtility]::UrlEncode($Relevance)
        }
        catch {
            # Use URI escape method as fallback
            $encodedRelevance = [uri]::EscapeDataString($Relevance)
        }
        
        $data = "relevance=$encodedRelevance"
        $response = $this.Post("query", $data, $Params)
        return $response
    }
    
    [array] SessionRelevanceArray([string]$Relevance, [hashtable]$Params = @{}) {
        $relResult = $this.SessionRelevanceXML($Relevance, $Params)
        $result = @()
        
        try {
            $xml = [xml]$relResult.Text
            $answers = $xml.SelectNodes("//Answer")
            
            if ($null -ne $answers -and $answers.Count -gt 0) {
                foreach ($item in $answers) {
                    $result += $item.InnerText
                }
            }
            else {
                $error = $xml.SelectSingleNode("//Error")
                if ($null -ne $error) {
                    $result += "ERROR: " + $error.InnerText
                }
            }
        }
        catch {
            Write-Error "Error processing relevance results: $_"
        }
        
        return $result
    }
    
    [string] SessionRelevanceString([string]$Relevance, [hashtable]$Params = @{}) {
        $relResultArray = $this.SessionRelevanceArray($Relevance, $Params)
        return $relResultArray -join "`n"
    }
    
    [bool] Connected() {
        try {
            $response = $this.Get("login")
            return $response.Request.StatusCode -eq 200
        }
        catch {
            return $false
        }
    }
    
    [bool] Login() {
        if (-not $this.Connected()) {
            try {
                $this.Get("login") | Out-Null
            }
            catch {
                Write-Error "Failed to login: $_"
                return $false
            }
        }
        
        return $this.Connected()
    }
    
    [void] Logout() {
        # Clear cookies from session and close
        $this.Session.Cookies.Clear()
    }
    
    [RESTResult] Upload([string]$FilePath, [string]$FileName) {
        if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
            throw "File not found or not readable: $FilePath"
        }
        
        # If file_name not specified, then get it from tail of file_path
        if ([string]::IsNullOrEmpty($FileName)) {
            $FileName = Split-Path -Path $FilePath -Leaf
        }
        
        $headers = @{
            "Content-Disposition" = "attachment; filename=`"$FileName`""
        }
        
        # Use byte array instead of raw content for binary-safe uploads
        $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
        
        $params = @{
            Headers = $headers
            ContentType = "application/octet-stream"
        }
        
        # Convert bytes to proper format for PowerShell Core
        return $this.Post($this.Url("upload"), $fileBytes, $params)
    }
    
    [void] ExportSiteContents([string]$SitePath, [string]$ExportFolder = "./", [int]$NameTrim = 70, [bool]$Verbose = $false) {
        if ($Verbose) {
            Write-Host "export_site_contents()"
        }
        
        # Iterate Over All Site Content
        $content = $this.Get("site/$SitePath/content")
        
        if ($Verbose) {
            Write-Host $content
        }
        
        if ($content.Request.StatusCode -eq 200) {
            $xml = [xml]$content.Text
            $itemCount = $xml.SelectNodes("/BESAPI/SiteContent/*").Count
            Write-Host "Archiving $itemCount items from $SitePath..."
            
            foreach ($item in $xml.SelectNodes("/BESAPI/SiteContent/*")) {
                if ($Verbose) {
                    Write-Host "{$SitePath} ($($item.LocalName)) [$($item.ID)] $($item.Name) - $($item.GetAttribute('LastModified'))"
                }
                
                # Get Specific Content
                $resourceUrl = $item.GetAttribute('Resource').Replace("http://", "https://")
                $contentResponse = $this.Get($resourceUrl)
                
                # Write Content to Disk
                if ($contentResponse) {
                    $sanitizedSitePath = Sanitize-Text $SitePath
                    $sanitizedTag = Sanitize-Text $item.LocalName
                    $sanitizedID = Sanitize-Text $item.ID
                    $sanitizedName = Sanitize-Text ($item.Name.Substring(0, [Math]::Min($item.Name.Length, $NameTrim)))
                    
                    $folderPath = Join-Path -Path $ExportFolder -ChildPath "$sanitizedSitePath/$sanitizedTag"
                    
                    if (-not (Test-Path -Path $folderPath)) {
                        New-Item -Path $folderPath -ItemType Directory -Force | Out-Null
                    }
                    
                    $filePath = Join-Path -Path $folderPath -ChildPath "$sanitizedID - $sanitizedName.bes"
                    # Use UTF8NoBOM for PowerShell Core
                    $contentResponse.Text | Out-File -FilePath $filePath -Encoding utf8NoBOM
                }
            }
        }
    }
    
    [void] ExportAllSites([bool]$IncludeExternal = $false, [string]$ExportFolder = "./", [int]$NameTrim = 70, [bool]$Verbose = $false) {
        $resultsSites = $this.Get("sites")
        
        if ($Verbose) {
            Write-Host $resultsSites
        }
        
        if ($resultsSites.Request.StatusCode -eq 200) {
            $xml = [xml]$resultsSites.Text
            
            foreach ($item in $xml.SelectNodes("/BESAPI/Sites/Site")) {
                $resourcePath = $item.GetAttribute('Resource')
                $sitePath = $resourcePath.Split('/api/site/', 2)[1]
                
                if ($IncludeExternal -or -not $sitePath.Contains("external/")) {
                    Write-Host "Exporting Site: $sitePath"
                    $this.ExportSiteContents($sitePath, $ExportFolder, $NameTrim, $Verbose)
                }
            }
        }
    }
}

class RESTResult {
    <#
    .SYNOPSIS
    BigFix REST API Result Abstraction Class
    #>
    
    [Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject]$Request
    [string]$Text
    [xml]$_BesXml
    [System.Xml.XmlDocument]$_BesObj
    [hashtable]$_BesDict
    [string]$_BesJson
    [bool]$Valid
    
    # Constructor
    RESTResult([Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject]$Request) {
        $this.Request = $Request
        
        # Properly handle content based on type (string or byte array)
        if ($Request.Content -is [byte[]]) {
            $this.Text = [System.Text.Encoding]::UTF8.GetString($Request.Content)
        }
        else {
            $this.Text = $Request.Content
        }
        
        # Check if response is valid XML
        if ($Request.Headers.ContainsKey("Content-Type") -and $Request.Headers["Content-Type"] -like "*application/xml*") {
            $this.Valid = $true
        }
        else {
            try {
                $xml = [xml]$this.Text
                $this.Valid = $true
            }
            catch {
                $this.Valid = $false
            }
        }
    }
    
    # Methods
    [string] ToString() {
        if ($this.Valid) {
            return $this.BesXml.OuterXml
        }
        else {
            return $this.Text
        }
    }
    
    [xml] GetBesXml() {
        if ($this.Valid -and $null -eq $this._BesXml) {
            try {
                $this._BesXml = [xml]$this.Text
            }
            catch {
                Write-Error "Failed to parse XML: $_"
            }
        }
        
        return $this._BesXml
    }
    
    [System.Xml.XmlDocument] GetBesObj() {
        if ($this.Valid -and $null -eq $this._BesObj) {
            try {
                $this._BesObj = [xml]$this.Text
            }
            catch {
                Write-Error "Failed to create XML object: $_"
            }
        }
        
        return $this._BesObj
    }
    
    [hashtable] GetBesDict() {
        if ($null -eq $this._BesDict) {
            if ($this.Valid) {
                try {
                    $xml = $this.GetBesXml()
                    if ($null -ne $xml) {
                        $this._BesDict = Convert-XmlElementToHashtable -Node $xml
                    }
                    else {
                        $this._BesDict = @{ "text" = $this.ToString() }
                    }
                }
                catch {
                    $this._BesDict = @{ "text" = $this.ToString() }
                }
            }
            else {
                $this._BesDict = @{ "text" = $this.ToString() }
            }
        }
        
        return $this._BesDict
    }
    
    [string] GetBesJson() {
        if ($null -eq $this._BesJson) {
            $this._BesJson = $this.GetBesDict() | ConvertTo-Json -Depth 10
        }
        
        return $this._BesJson
    }
    
    # Properties
    [xml] BesXml { 
        get { return $this.GetBesXml() }
    }
    
    [System.Xml.XmlDocument] BesObj {
        get { return $this.GetBesObj() }
    }
    
    [hashtable] BesDict {
        get { return $this.GetBesDict() }
    }
    
    [string] BesJson {
        get { return $this.GetBesJson() }
    }
}

# Export functions and classes for module
Export-ModuleMember -Function Sanitize-Text, Convert-XmlElementToHashtable

<#
.SYNOPSIS
Creates a new BigFix REST API connection.

.DESCRIPTION
Creates and returns a new BESConnection object for interacting with the BigFix REST API.

.PARAMETER Username
The username for authentication.

.PARAMETER Password
The password for authentication.

.PARAMETER RootServer
The BigFix root server address.

.PARAMETER Verify
Whether to verify SSL certificates.

.EXAMPLE
$bes = New-BESConnection -Username "admin" -Password "password" -RootServer "bigfix.example.com"
#>
function New-BESConnection {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Username,
        
        [Parameter(Mandatory = $true)]
        [string]$Password,
        
        [Parameter(Mandatory = $true)]
        [string]$RootServer,
        
        [Parameter(Mandatory = $false)]
        [bool]$Verify = $false
    )
    
    return [BESConnection]::new($Username, $Password, $RootServer, $Verify)
}

Export-ModuleMember -Function New-BESConnection