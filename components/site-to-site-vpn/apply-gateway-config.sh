#!/bin/bash
# Manual Gateway Configuration Script
# Execute this to configure the gateway VM

echo "=========================================="
echo "Configuring VPN Gateway VM"
echo "=========================================="

# Run these commands on the gateway VM
oc exec -n windows-non-prod virt-launcher-vpn-gateway-s65xr -c compute -- sh -c '
set -x

# Configure iptables NAT for CUDN traffic
echo "Configuring NAT rules..."
iptables -t nat -A POSTROUTING -s 10.227.128.0/21 -o eth0 -j MASQUERADE

# Allow forwarding
echo "Configuring forwarding rules..."
iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o eth1 -d 10.227.128.0/21 -j ACCEPT   # on-prem → VM (e.g. RDP)
iptables -A FORWARD -i eth0 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i eth1 -o eth1 -j ACCEPT

# Verify configuration
echo ""
echo "=== Configuration Applied ==="
echo "IP Forwarding:"
sysctl net.ipv4.ip_forward
echo ""
echo "Network Interfaces:"
ip -br addr show
echo ""
echo "NAT Rules:"
iptables -t nat -L POSTROUTING -n -v
echo ""
echo "Forwarding Rules:"
iptables -L FORWARD -n -v
echo "=========================================="
'

echo ""
echo "✓ Gateway VM configuration complete!"
echo ""
echo "Next steps:"
echo "1. Test gateway connectivity from Windows VM"
echo "2. Configure Windows VMs to use gateway IP: 10.227.128.15"
echo "=========================================="
