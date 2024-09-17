## Essa parte do código levanta os Softwares

    function Get-InstalledApps {
        Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" |
        Select-Object DisplayName, DisplayVersion |
        Where-Object { $_.DisplayName -ne $null } |
        Sort-Object DisplayName
    }

    # Adicionar os campos 'Type' e 'Platform' a cada item
    $installedAppsWithFields = Get-InstalledApps | ForEach-Object {
        [PSCustomObject]@{
            Name   = $_.DisplayName
            Version = $_.DisplayVersion
            Type           = "Software"
            Platform       = "Windows"
        }
    }


## Essa parte do código levanta as extensãoes dos navegadores

$newApp1 = [PSCustomObject]@{
    Name   = "Universal CRT Tools x64"
    Version = "10.1.22621.3233"
    Type           = "Extension"
    Platform       = "Chrome"
}

$newApp2 = [PSCustomObject]@{
    Name   = "Universal CRT Tools x64"
    Version = "101231233233"
    Type           = "Extension"
    Platform       = "Chrome"
}

$newApp3 = [PSCustomObject]@{
    Name   = "Universal CRasdTools x64"
    Version = "10.1.22621.3233"
    Type           = "Extension"
    Platform       = "Chrome"
}

$newApp4 = [PSCustomObject]@{
    Name   = "VS WCF Debugging"
    Version = "17.0.157.0"
    Type           = "Extension"
    Platform       = "Edge"
}

$newApp5 = [PSCustomObject]@{
    Name   = "vs_minshellinteropx64msi"
    Version = "17.11.35102"
    Type           = "Extension"
    Platform       = "Firefox"
}

# Essa parte do código levanta as extensãoes os plug-ins

$newApp6 = [PSCustomObject]@{
    Name   = ".NET MAUI Templates (x64)"
    Version = "7.0.20.0"
    Type           = "Plug-in"
    Platform       = "VsCode"
}

$newApp7 = [PSCustomObject]@{
    Name   = ".NET MAUI Templates (x64)"
    Version = "7.04124124.20.023123412412"
    Type           = "Plug-in"
    Platform       = "VsCode"
}

$newApp8 = [PSCustomObject]@{
    Name   = "vs_minshellintasdasderopx64msi"
    Version = "17.11.35102"
    Type           = "Plug-in"
    Platform       = "VsCode"
}

# Exibir a lista de aplicativos instalados com os novos campos
$installedAppsWithFields + $newApp1 + $newApp2 + $newApp3 + $newApp4 + $newApp5 + $newApp6 + $newApp7 + $newApp8 | Select-Object Name, Version, Type, Platform | ConvertTo-Csv -NoTypeInformation
