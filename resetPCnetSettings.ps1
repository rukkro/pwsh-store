############################################
#            ADAPTER SETTINGS              #
############################################

# Get names of all adapters on PC
$all_adapters = Get-NetAdapter | Select-Object -ExpandProperty "Name"

# Stores domain number this PC resides in
$domain_num

# Highest domain num (dom1 - dom6 in this case)
$max_domain_num = 6

foreach($adapter_name in $all_adapters){

	# Enable the adapter if it's disabled
	Enable-NetAdapter -Name $adapter_name

	$IPType = "IPv4"

	# Get adapter & its ipv4 interface
	$adapter = Get-NetAdapter -Name $adapter_name
	$interface = $adapter | Get-NetIPInterface -AddressFamily $IPType

	# Check if DHCP is disabled
	If ($interface.Dhcp -eq "Disabled") {

		# Remove existing gateway
		If (($interface | Get-NetIPConfiguration).Ipv4DefaultGateway) {
			$interface | Remove-NetRoute -Confirm:$false
		}

		# Enable DHCP
		$interface | Set-NetIPInterface -DHCP Enabled

		# Configure the DNS Servers automatically
		$interface | Set-DnsClientServerAddress -ResetServerAddresses
	}
	# Get IP Address of adapter
	$ipv4_address = $adapter | Get-NetIPAddress -AddressFamily IPv4 | Select-Object -ExpandProperty "IPAddress"
	
	# If adapter has IP starting with 10.0.0.X
	If ($ipv4_address.StartsWith("10.0.0.")) {
		Rename-NetAdapter -Name $adapter_name "Internet Connection"
		
		# Prevent internet adapter from DNS registration
		$adapter | set-dnsclient -RegisterThisConnectionsAddress $false
	}
	# If adapter has IP starting with 10.0.X.Y (domain adapter)
	elseif ($ipv4_address.StartsWith("10.0.")){
		# Rename it
		Rename-NetAdapter -Name $adapter_name "LAN Connection"
		
		# Get the domain number from its IP address
		# This assumes the switch/router are set up correctly
		$last_dot = $ipv4_address.LastIndexOf(".")
		$dot_before_last_dot = $ipv4_address.LastIndexOf(".",$last_dot - 1)  + 1
		# Get substring of IP address to get domain_num. Second arg of .substring() is the length of substring 
		$domain_num = $ipv4_address.substring($dot_before_last_dot,($last_dot - $dot_before_last_dot))
		echo "Domain number is " $domain_num
		
		# Allow domain adapter to do DNS registration
		$adapter | set-dnsclient -RegisterThisConnectionsAddress $true
	}
}

############################################
#            PERSISTENT ROUTES             #
############################################

# Remove existing routes
route delete 0.0.0.0
route delete 10.0.0.0

### Internet Connection ### 

# Get adapter by name
$adapter = Get-NetAdapter -Name "Internet Connection"
# Getting interface index (necessary for persistent route to become active)
$interface_index = $adapter | Select-Object -ExpandProperty InterfaceIndex

# Add persistent route
# Direct traffic not destined for another domain through the "Internet Connection" adapter.
route -p add 0.0.0.0 mask 0.0.0.0 10.0.0.3 if $interface_index
route -p add 10.0.0.0 mask 255.255.255.0 10.0.0.3 if $interface_index

### LAN Connection ### 

# Get adapter by name
$adapter = Get-NetAdapter -Name "LAN Connection"
# Getting interface index (necessary for persistent route to become active)
$interface_index = $adapter | Select-Object -ExpandProperty InterfaceIndex

# Add persistent routes. Direct domain router traffic.
# If traffic is destined for another domain (10.0.X.Y), route it through the domain router.
for($i=1;$i -le $max_domain_num;$i++){
	route delete 10.0.$i.0
	route -p add 10.0.$i.0 mask 255.255.255.0 10.0.$domain_num.1 if $interface_index
}

############################################
#            ENABLE FIREWALL               #
############################################
echo "Enabling Firewall..."
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True

############################################
#            DISABLE PROXY                 #
############################################
echo "Disabling Proxy..."
set-itemproperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -name ProxyEnable -value 0 

############################################
#            REMOTE DESKTOP                #
############################################
# https://exchangepedia.com/2016/10/enable-remote-desktop-rdp-connections-for-admins-on-windows-server-2016.html

# Enable RDP Connections
Set-ItemProperty ‘HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\‘ -Name “fDenyTSConnections” -Value 0

# Enable Network Level Authentication
Set-ItemProperty ‘HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp\‘ -Name “UserAuthentication” -Value 1

# Enable Windows firewall rules to allow incoming RDP
Enable-NetFirewallRule -DisplayGroup “Remote Desktop”

############################################
#            TFTP FIREWALL RULE            #
############################################
# TFTP uses port 69 w/ UDP. This adds a new rule that allows it.
# This should make configuring tftpd64's firewall rules unecessary.
New-NetFirewallRule -DisplayName 'TFTP' -Profile @('Domain', 'Private', 'Public') -Direction Inbound -Action Allow -Protocol UDP -LocalPort '69'
