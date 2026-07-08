#  for lazy me...
# ==============================================================================
# Credit: ThioJoe (https://github.com/ThioJoe/Windows-Sandbox-Tools)
# Modified for Auto-Elevate, Direct Host Install, and Auto-Cleanup
# ==============================================================================

# 1. Auto-Elevate Module
$scriptUrl = "https://kahao.github.io/tools/install-store-winget.ps1" # CHANGE THIS TO YOUR URL
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Admin Privileges..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm $scriptUrl | iex`""
    Exit
}

$ProgressPreference = 'SilentlyContinue'
$dlFolder = (New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path
$workDir = Join-Path $dlFolder "ThioJoe_Install_Temp"
if (Test-Path $workDir) { Remove-Item -Path $workDir -Recurse -Force }
New-Item -Path $workDir -ItemType Directory -Force | Out-Null

Write-Host "Starting automated deployment of MS Store and Winget..." -ForegroundColor Green

# ==============================================================================
# PART 1: MICROSOFT STORE INSTALLATION
# ==============================================================================
Write-Host "`n[1/2] Fetching Microsoft Store via Windows Update API..." -ForegroundColor Cyan

$osBuild = [Environment]::OSVersion.Version.Build
$branch = if ($osBuild -ge 26100) { "ge_release" } elseif ($osBuild -ge 22000) { "ni_release" } else { "vb_release" }
$baseUri = "https://fe3.delivery.mp.microsoft.com/ClientWebService/client.asmx"
$headers = @{ "Content-Type" = "application/soap+xml; charset=utf-8" }

# XML Templates (Minified)
$xmlCookie = @"
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:a="http://www.w3.org/2005/08/addressing"><s:Header><a:Action s:mustUnderstand="1">http://www.microsoft.com/SoftwareDistribution/Server/ClientWebService/GetCookie</a:Action><a:MessageID>urn:uuid:$(New-Guid)</a:MessageID><a:To s:mustUnderstand="1">https://fe3.delivery.mp.microsoft.com/ClientWebService/client.asmx</a:To><o:Security s:mustUnderstand="1" xmlns:o="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"><wuws:WindowsUpdateTicketsToken wsu:id="ClientMSA" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" xmlns:wuws="http://schemas.microsoft.com/msus/2014/10/WindowsUpdateAuthorization"><TicketType Name="MSA" Version="1.0" Policy="MBI_SSL"><user></user></TicketType></wuws:WindowsUpdateTicketsToken></o:Security></s:Header><s:Body><GetCookie xmlns="http://www.microsoft.com/SoftwareDistribution/Server/ClientWebService" /></s:Body></s:Envelope>
"@

$xmlList = @"
<s:Envelope xmlns:a="http://www.w3.org/2005/08/addressing" xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Header><a:Action s:mustUnderstand="1">http://www.microsoft.com/SoftwareDistribution/Server/ClientWebService/SyncUpdates</a:Action><a:MessageID>urn:uuid:$(New-Guid)</a:MessageID><a:To s:mustUnderstand="1">https://fe3cr.delivery.mp.microsoft.com/ClientWebService/client.asmx</a:To><o:Security s:mustUnderstand="1" xmlns:o="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"><Timestamp xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd"><Created>$((Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'"))</Created><Expires>$((Get-Date).AddMinutes(5).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'"))</Expires></Timestamp><wuws:WindowsUpdateTicketsToken wsu:id="ClientMSA" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" xmlns:wuws="http://schemas.microsoft.com/msus/2014/10/WindowsUpdateAuthorization"><TicketType Name="MSA" Version="1.0" Policy="MBI_SSL"><user/></TicketType></wuws:WindowsUpdateTicketsToken></o:Security></s:Header><s:Body><SyncUpdates xmlns="http://www.microsoft.com/SoftwareDistribution/Server/ClientWebService"><cookie><Expiration>$((Get-Date).AddYears(10).ToUniversalTime().ToString('u').Replace(' ','T'))</Expiration><EncryptedData>{0}</EncryptedData></cookie><parameters><ExpressQuery>false</ExpressQuery><InstalledNonLeafUpdateIDs><int>1</int><int>2</int><int>3</int><int>11</int><int>19</int><int>2359974</int><int>5169044</int><int>8788830</int><int>23110993</int><int>23110994</int><int>54341900</int><int>59830006</int><int>59830007</int><int>59830008</int><int>60484010</int><int>62450018</int><int>62450019</int><int>62450020</int><int>98959022</int><int>98959023</int><int>98959024</int><int>98959025</int><int>98959026</int><int>104433538</int><int>129905029</int><int>130040031</int><int>132387090</int><int>132393049</int><int>133399034</int><int>138537048</int><int>140377312</int><int>143747671</int><int>158941041</int><int>158941042</int><int>158941043</int><int>158941044</int><int>159123858</int><int>159130928</int><int>164836897</int><int>164847386</int><int>164848327</int><int>164852241</int><int>164852246</int><int>164852253</int></InstalledNonLeafUpdateIDs><SkipSoftwareSync>false</SkipSoftwareSync><NeedTwoGroupOutOfScopeUpdates>false</NeedTwoGroupOutOfScopeUpdates><FilterAppCategoryIds><CategoryIdentifier><Id>64293252-5926-453c-9494-2d4021f1c78d</Id></CategoryIdentifier></FilterAppCategoryIds><TreatAppCategoryIdsAsInstalled>true</TreatAppCategoryIdsAsInstalled><AlsoPerformRegularSync>false</AlsoPerformRegularSync><ComputerSpec/><ExtendedUpdateInfoParameters><XmlUpdateFragmentTypes><XmlUpdateFragmentType>Extended</XmlUpdateFragmentType></XmlUpdateFragmentTypes><Locales><string>en-US</string><string>en</string></Locales></ExtendedUpdateInfoParameters><ClientPreferredLanguages><string>en-US</string></ClientPreferredLanguages><ProductsParameters><SyncCurrentVersionOnly>false</SyncCurrentVersionOnly><DeviceAttributes>E:BranchReadinessLevel=CB&amp;CurrentBranch={1}&amp;OEMModel=Virtual%20Machine&amp;FlightRing=Retail&amp;AttrDataVer=321&amp;InstallLanguage=en-US&amp;OSUILocale=en-US&amp;InstallationType=Client&amp;FlightingBranchName=&amp;OSSkuId=48&amp;App=WU_STORE&amp;ProcessorManufacturer=GenuineIntel&amp;OEMName_Uncleaned=Microsoft%20Corporation&amp;AppVer=1407.2503.28012.0&amp;OSArchitecture=AMD64&amp;IsFlightingEnabled=1&amp;TelemetryLevel=1&amp;DefaultUserRegion=39070&amp;WuClientVer=1310.2503.26012.0&amp;OSVersion=10.0.$osBuild.0&amp;DeviceFamily=Windows.Desktop</DeviceAttributes><CallerAttributes>Interactive=1;IsSeeker=1;</CallerAttributes><Products/></ProductsParameters></parameters></SyncUpdates></s:Body></s:Envelope>
"@

$xmlUrl = @"
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:a="http://www.w3.org/2005/08/addressing"><s:Header><a:Action s:mustUnderstand="1">http://www.microsoft.com/SoftwareDistribution/Server/ClientWebService/GetExtendedUpdateInfo2</a:Action><a:MessageID>urn:uuid:$(New-Guid)</a:MessageID><a:To s:mustUnderstand="1">https://fe3cr.delivery.mp.microsoft.com/ClientWebService/client.asmx/secured</a:To><o:Security s:mustUnderstand="1" xmlns:o="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"><u:Timestamp u:Id="_0" xmlns:u="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd"><u:Created>$((Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'"))</u:Created><u:Expires>$((Get-Date).AddMinutes(5).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'"))</u:Expires></u:Timestamp><wuws:WindowsUpdateTicketsToken wsu:id="ClientMSA" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" xmlns:wuws="http://schemas.microsoft.com/msus/2014/10/WindowsUpdateAuthorization"><TicketType Name="MSA" Version="1.0" Policy="MBI_SSL"><user>{0}</user></TicketType></wuws:WindowsUpdateTicketsToken></o:Security></s:Header><s:Body><GetExtendedUpdateInfo2 xmlns="http://www.microsoft.com/SoftwareDistribution/Server/ClientWebService"><updateIDs><UpdateIdentity><UpdateID>{1}</UpdateID><RevisionNumber>{2}</RevisionNumber></UpdateIdentity></updateIDs><infoTypes><XmlUpdateFragmentType>FileUrl</XmlUpdateFragmentType></infoTypes><DeviceAttributes>E:BranchReadinessLevel=CB&amp;CurrentBranch={3}&amp;OEMModel=Virtual%20Machine&amp;FlightRing=Retail&amp;AttrDataVer=321&amp;InstallLanguage=en-US&amp;OSUILocale=en-US&amp;InstallationType=Client&amp;FlightingBranchName=&amp;OSSkuId=48&amp;App=WU_STORE&amp;ProcessorManufacturer=GenuineIntel&amp;OEMName_Uncleaned=Microsoft%20Corporation&amp;AppVer=1407.2503.28012.0&amp;OSArchitecture=AMD64&amp;IsFlightingEnabled=1&amp;TelemetryLevel=1&amp;DefaultUserRegion=39070&amp;WuClientVer=1310.2503.26012.0&amp;OSVersion=10.0.$osBuild.0&amp;DeviceFamily=Windows.Desktop</DeviceAttributes></GetExtendedUpdateInfo2></s:Body></s:Envelope>
"@

# API Requests
$cookieRes = [xml](Invoke-WebRequest -Uri $baseUri -Method Post -Body $xmlCookie -Headers $headers -UseBasicParsing).Content
$cookie = $cookieRes.Envelope.Body.GetCookieResponse.GetCookieResult.EncryptedData

Add-Type -AssemblyName System.Web
$listRes = Invoke-WebRequest -Uri $baseUri -Method Post -Body ($xmlList -f $cookie, $branch) -Headers $headers -UseBasicParsing
$listXml = [xml]([System.Web.HttpUtility]::HtmlDecode($listRes.Content))

$sysArch = switch ($env:PROCESSOR_ARCHITECTURE) { "AMD64" {"x64"} "ARM64" {"arm64"} "x86" {"x86"} default {"unknown"} }
$allUpdates = $listXml.Envelope.Body.SyncUpdatesResponse.SyncUpdatesResult.ExtendedUpdateInfo.Updates.Update
$downloads = $listXml.Envelope.Body.SyncUpdatesResponse.SyncUpdatesResult.NewUpdates.UpdateInfo | Where-Object { $_.Xml.Properties.SecuredFragment }

$dlQueue = @()
foreach ($u in $downloads) {
    $ext = $allUpdates | Where-Object { $_.ID -eq $u.ID } | Select-Object -First 1
    $fNode = $ext.Xml.Files.File | Where-Object { $_.FileName -notlike "Abm_*" } | Select-Object -First 1
    if ($fNode) {
        $idStr = $fNode.GetAttribute("InstallerSpecificIdentifier")
        if ($idStr -match "^(?<Name>.+?)_(?<Ver>\d+\.\d+\.\d+\.\d+)_(?<Arch>[a-zA-Z0-9]+)_.*$") {
            if ($matches.Name -eq 'Microsoft.WindowsStore' -or $matches.Arch -eq $sysArch -or $matches.Arch -eq 'neutral') {
                $dlQueue += [PSCustomObject]@{ UID=$u.Xml.UpdateIdentity.UpdateID; Rev=$u.Xml.UpdateIdentity.RevisionNumber; Name=$idStr; File=$fNode.FileName }
            }
        }
    }
}

# Download & Install Store Components
Write-Host "Downloading Store dependencies and bundles..." -ForegroundColor Yellow
$storeFiles = @()
foreach ($pkg in $dlQueue) {
    $urlRes = [xml](Invoke-WebRequest -Uri "$baseUri/secured" -Method Post -Body ($xmlUrl -f $cookie, $pkg.UID, $pkg.Rev, $branch) -Headers $headers -UseBasicParsing).Content
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($pkg.File)
    $url = ($urlRes.Envelope.Body.GetExtendedUpdateInfo2Response.GetExtendedUpdateInfo2Result.FileLocations.FileLocation | Where-Object { $_.Url -like "*$baseName*" }).Url
    if ($url) {
        $out = Join-Path $workDir "$($pkg.Name)$([System.IO.Path]::GetExtension($pkg.File))"
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
        $storeFiles += $out
    }
}

Write-Host "Installing Store packages..." -ForegroundColor Yellow
foreach ($dep in @('Microsoft.VCLibs','Microsoft.NET.Native.Framework','Microsoft.NET.Native.Runtime','Microsoft.UI.Xaml')) {
    $storeFiles | Where-Object { $_ -like "*$dep*" } | Sort-Object | ForEach-Object { Add-AppxPackage -Path $_ -ErrorAction SilentlyContinue }
}
$storeBundle = $storeFiles | Where-Object { $_ -like "*Microsoft.WindowsStore*" } | Select-Object -First 1
if ($storeBundle) { Add-AppxPackage -Path $storeBundle }

# Fix Region registry for Store functionality
$geoKey = "HKCU:\Control Panel\International\Geo"
if (-not (Test-Path $geoKey)) { New-Item -Path $geoKey -Force | Out-Null }
Set-ItemProperty -Path $geoKey -Name "Nation" -Value "244"
Set-ItemProperty -Path $geoKey -Name "Name" -Value "US"


# ==============================================================================
# PART 2: WINGET INSTALLATION
# ==============================================================================
Write-Host "`n[2/2] Fetching Winget from GitHub via API..." -ForegroundColor Cyan

$rel = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -UseBasicParsing
$msixUrl = ($rel.assets | Where-Object { $_.name -match '\.msixbundle$' }).browser_download_url
$zipUrl = ($rel.assets | Where-Object { $_.name -match 'Dependencies\.zip$' }).browser_download_url

$wingetMsix = Join-Path $workDir "winget.msixbundle"
$depsZip = Join-Path $workDir "deps.zip"
$depsExt = Join-Path $workDir "deps_extracted"

Write-Host "Downloading Winget and dependencies..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $msixUrl -OutFile $wingetMsix -UseBasicParsing
Invoke-WebRequest -Uri $zipUrl -OutFile $depsZip -UseBasicParsing

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($depsZip, $depsExt)

Write-Host "Installing Winget dependencies..." -ForegroundColor Yellow
Get-ChildItem -Path "$depsExt\$sysArch" -Filter *.appx -Recurse | ForEach-Object { Add-AppxPackage -Path $_.FullName -ErrorAction SilentlyContinue }

Write-Host "Installing Winget..." -ForegroundColor Yellow
Add-AppxPackage -Path $wingetMsix

# ==============================================================================
# PART 3: CLEANUP
# ==============================================================================
Write-Host "`n[+] Cleaning up downloaded files..." -ForegroundColor Cyan
Remove-Item -Path $workDir -Recurse -Force

Write-Host "Done! Microsoft Store and Winget are installed and ready." -ForegroundColor Green
Write-Host "Press any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
