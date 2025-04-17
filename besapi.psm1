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

        # Modify RootServer and assign to $this.RootServer
        $modifiedRootServer = $RootServer
        if (-not $modifiedRootServer.StartsWith("http")) {
            $modifiedRootServer = "https://" + $modifiedRootServer
        }
        if (($modifiedRootServer.ToCharArray() | Where-Object { $_ -eq ':' } | Measure-Object).Count -ne 2) {
            $modifiedRootServer = $modifiedRootServer + ":52311"
        }

        $this.RootServer = $modifiedRootServer

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
    
    [string] Get([string]$Path = "help", [hashtable]$Params = @{}) {
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
        return $response
    }
    
    [string] Post([string]$Path, [string]$Data, [hashtable]$Params = @{}) {
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
        return $response
    }
    
    [string] Put([string]$Path, [string]$Data, [hashtable]$Params = @{}) {
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
        return $response
    }
    
    [string] Delete([string]$Path, [hashtable]$Params = @{}) {
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
        return $response
    }
    
    [string] SessionRelevanceXML([string]$Relevance, [hashtable]$Params = @{}) {
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
    
    Logout() {
        # Clear cookies from session and close
        $this.Session.Cookies.Clear()
    }
    
    [string] Upload([string]$FilePath, [string]$FileName) {
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
}

function Get-BESConnection {
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

Export-ModuleMember -Function Sanitize-Text, Convert-XmlElementToHashtable, Get-BESConnection, BESConnection
