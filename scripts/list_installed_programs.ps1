function Get-InstalledApps {
    Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" |
    Select-Object DisplayName, DisplayVersion |
    Where-Object { $_.DisplayName -ne $null } |
    Sort-Object DisplayName
}

# Obter aplicativos instalados
$installedApps = Get-InstalledApps

# Exibir a lista de aplicativos instalados
$installedApps | Select-Object DisplayName, DisplayVersion | ConvertTo-Csv -NoTypeInformation