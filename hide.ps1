$registryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
$name = "{2cc5ca98-6485-489a-920e-b3e88a6ccce3}"
if (-not (Test-Path $registryPath)) { New-Item -Path $registryPath -Force | Out-Null }
New-ItemProperty -Path $registryPath -Name $name -Value 1 -PropertyType DWORD -Force | Out-Null
Stop-Process -Name explorer -Force
