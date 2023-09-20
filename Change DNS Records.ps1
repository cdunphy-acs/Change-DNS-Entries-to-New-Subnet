# Define variables for the DNS server and the old and new subnets
$DNSServer = Read-Host -Prompt 'Input your DNS Server'
$ZoneName = Read-Host -Prompt 'Input your Zone Name'
$OldSubnet = Read-Host -Prompt 'Input your Old Subnet'  # For example, "192.168.1.0/24"
$NewSubnet = Read-Host -Prompt 'Input your New Subnet'  # For example, "192.168.2.0/24"

function Test-IsInSubnet {
    param (
        [string]$IPAddress,
        [string]$Subnet
    )

    # Parse the IP address and subnet
    $ip = [System.Net.IPAddress]::Parse($IPAddress)
    $subnetIP = [System.Net.IPAddress]::Parse($Subnet.Split('/')[0])
    $subnetPrefixLength = [int]$Subnet.Split('/')[1]

    Write-Host "IP Address: $($ip.IPAddressToString)"
    Write-Host "Subnet IP: $($subnetIP.IPAddressToString)"
    Write-Host "Subnet Prefix Length: $subnetPrefixLength"

    # Convert IP address and subnet to byte arrays
    $ipBytes = $ip.GetAddressBytes()
    Write-Host "IP Address Bytes: $ipBytes"

    $subnetBytes = $subnetIP.GetAddressBytes()
    Write-Host "Subnet Bytes: $subnetBytes"

    # Calculate the network address for the IP address and subnet
    for ($i = 0; $i -lt ($subnetPrefixLength / 8); $i++) {
        if ($ipBytes[$i] -ne $subnetBytes[$i]) {
            Write-Host "Network Address Byte $($i): Different"
            return $false
        }
        Write-Host "Network Address Byte $($i): Same"
    }

    return $true
}

# Function to get a new IP address within the new subnet
function Get-NewIPAddressInSubnet {
    param (
        [string]$OldIPAddress,
        [string]$OldSubnet,
        [string]$NewSubnet
    )

    # Parse the IP address and subnet
    $oldIP = [System.Net.IPAddress]::Parse($OldIPAddress)
    $oldSubnetIP = [System.Net.IPAddress]::Parse($OldSubnet.Split('/')[0])
    $newSubnetIP = [System.Net.IPAddress]::Parse($NewSubnet.Split('/')[0])

    # Convert IP address and subnet to byte arrays
    $oldIPBytes = $oldIP.GetAddressBytes()
    $oldSubnetBytes = $oldSubnetIP.GetAddressBytes()
    $newSubnetBytes = $newSubnetIP.GetAddressBytes()

    # Calculate the new IP address within the new subnet
    for ($i = 0; $i -lt 4; $i++) {
        if ($oldIPBytes[$i] -ne $oldSubnetBytes[$i]) {
            break
        }
        else {
            $oldIPBytes[$i] = $newSubnetBytes[$i]
        }
    }

    # Convert new IP address bytes to IP address
    $newIPAddress = [System.Net.IPAddress]::new($oldIPBytes)

    return $newIPAddress.IPAddressToString
}

# Get all DNS zones on the specified DNS server
$Zones = Get-DnsServerZone -ComputerName $DNSServer

# Iterate through each DNS zone and fetch DNS records
foreach ($Zone in $Zones) {
    if ($Zone.ZoneName -eq $ZoneName) {
        Write-Host "Processing DNS zone: $($Zone.ZoneName)"
        
        $Records = Get-DnsServerResourceRecord -ZoneName $Zone.ZoneName -ComputerName $DNSServer

        # Iterate through each record and update if it's in the old subnet
        foreach ($Record in $Records) {
            if ($null -ne $Record.RecordData.IPv4Address) {
                $RecordIPAddress = $Record.RecordData.IPv4Address.ToString()

                if (Test-IsInSubnet -IPAddress $RecordIPAddress -Subnet $OldSubnet) {
                    $NewIPAddress = Get-NewIPAddressInSubnet -OldIPAddress $RecordIPAddress -OldSubnet $OldSubnet -NewSubnet $NewSubnet

                    # Modify the DNS record with the new IP address
                    $recordClone = $Record.Clone()
                    $recordClone.RecordData.IPv4Address = [System.Net.IPAddress]::Parse($NewIPAddress)
                    Set-DnsServerResourceRecord -ZoneName $Zone.ZoneName -OldInputObject $Record -NewInputObject $recordClone -ComputerName $DNSServer
                    Write-Host "Updated DNS record: $($Record.HostName) -> $NewIPAddress"

                }
            }
            else {
                Write-Host "Skipping DNS record: $($Record.HostName) (Not in old subnet)"
            }
        }
    }
}
