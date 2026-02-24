#!/bin/bash
# Gateway VM Configuration Script
# Run this via: virtctl console vpn-gateway -n windows-non-prod
# Then paste these commands

set -x

# Reconfigure eth1 to use 10.227.128.1 instead of DHCP-assigned IP
echo "=========================================="
echo "Reconfiguring Gateway VM Network"
echo "=========================================="

# Remove existing IP on eth1
ip addr del 10.227.128.15/21 dev eth1 2>/dev/null || true

# Add static IP 10.227.128.1/21
ip addr add 10.227.128.1/21 dev eth1

# Verify
ip addr show eth1

# Update NetworkManager configuration for persistence
cat > /etc/sysconfig/network-scripts/ifcfg-eth1 <<EOF
DEVICE=eth1
BOOTPROTO=none
ONBOOT=yes
IPADDR=10.227.128.1
PREFIX=21
EOF

# Reload NetworkManager
nmcli con reload

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.all.rp_filter=0
sysctl -w net.ipv4.conf.default.rp_filter=0

# Configure iptables NAT
echo "Configuring NAT and forwarding rules..."

# NAT for CUDN traffic going to pod network
iptables -t nat -A POSTROUTING -s 10.227.128.0/21 -o eth0 -j MASQUERADE

# Allow forwarding
iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o eth1 -d 10.227.128.0/21 -j ACCEPT   # on-prem → VM (e.g. RDP)
iptables -A FORWARD -i eth0 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i eth1 -o eth1 -j ACCEPT

# Save iptables
iptables-save > /etc/sysconfig/iptables

# Enable iptables service
systemctl enable iptables 2>/dev/null || true
systemctl start iptables 2>/dev/null || true

echo "=========================================="
echo "Gateway Configuration Complete!"
echo "=========================================="
echo "Interface Status:"
ip -br addr show
echo ""
echo "Routing Table:"
ip route show
echo ""
echo "NAT Rules:"
iptables -t nat -L -n -v | grep -E "Chain|10.227.128"
echo ""
echo "Test connectivity:"
echo "  ping 8.8.8.8"
echo "=========================================="
