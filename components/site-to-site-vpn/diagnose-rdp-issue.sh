#!/bin/bash
# Quick Diagnostic Test for RDP Connectivity Issues

echo "=========================================="
echo "  RDP Connectivity Diagnostic Test"
echo "=========================================="
echo ""

# Check if logged into OpenShift
if ! oc whoami &>/dev/null; then
    echo "❌ ERROR: Not logged into OpenShift"
    echo "Please login first: oc login https://api.non-prod.5wp0.p3.openshiftapps.com:443"
    exit 1
fi

echo "✅ Logged into OpenShift as: $(oc whoami)"
echo ""

# Check VM status
echo "=== VM Status ==="
oc get vmi nymsdv297 nymsdv301 -n windows-non-prod -o custom-columns=NAME:.metadata.name,IP:.status.interfaces[0].ipAddress,STATUS:.status.phase,NODE:.status.nodeName --no-headers 2>/dev/null || echo "❌ VMs not found or not running"
echo ""

# Create test pod on same network
echo "=== Creating test pod on windows-non-prod network ==="
cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: network-test-diagnostic
  namespace: windows-non-prod
  annotations:
    k8s.v1.cni.cncf.io/networks: windows-non-prod
spec:
  containers:
  - name: test
    image: nicolaka/netshoot
    command: ["sleep", "3600"]
EOF

echo "Waiting for test pod to be ready..."
oc wait --for=condition=Ready pod/network-test-diagnostic -n windows-non-prod --timeout=60s 2>/dev/null
if [ $? -ne 0 ]; then
    echo "❌ Test pod failed to start"
    exit 1
fi

echo "✅ Test pod ready"
echo ""

# Get test pod IP
TEST_POD_IP=$(oc get pod network-test-diagnostic -n windows-non-prod -o jsonpath='{.status.podIPs[1].ip}' 2>/dev/null)
echo "Test pod secondary IP: $TEST_POD_IP"
echo ""

# Test 1: Ping VMs from test pod
echo "=== Test 1: Ping VMs from test pod (same network) ==="
echo "Testing NYMSDV297 (10.132.104.10)..."
oc exec network-test-diagnostic -n windows-non-prod -- ping -c 2 10.132.104.10 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Can ping NYMSDV297"
else
    echo "❌ Cannot ping NYMSDV297 - VM or network issue"
fi

echo ""
echo "Testing NYMSDV301 (10.132.104.11)..."
oc exec network-test-diagnostic -n windows-non-prod -- ping -c 2 10.132.104.11 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Can ping NYMSDV301"
else
    echo "❌ Cannot ping NYMSDV301 - VM or network issue"
fi
echo ""

# Test 2: Ping gateway
echo "=== Test 2: Ping gateway (10.132.104.1) ==="
oc exec network-test-diagnostic -n windows-non-prod -- ping -c 2 10.132.104.1 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Gateway is reachable"
else
    echo "❌ Gateway not reachable - networking issue"
fi
echo ""

# Test 3: Check RDP port
echo "=== Test 3: Check RDP port (TCP 3389) ==="
echo "Testing NYMSDV297:3389..."
oc exec network-test-diagnostic -n windows-non-prod -- nc -zv 10.132.104.10 3389 2>&1 | tail -1
echo ""
echo "Testing NYMSDV301:3389..."
oc exec network-test-diagnostic -n windows-non-prod -- nc -zv 10.132.104.11 3389 2>&1 | tail -1
echo ""

# Test 4: Check ARP table
echo "=== Test 4: ARP Table (shows MAC addresses) ==="
oc exec network-test-diagnostic -n windows-non-prod -- arp -n | grep "10.132.104"
echo ""

# Test 5: Traceroute
echo "=== Test 5: Traceroute to company network (if configured) ==="
echo "Attempting to reach 10.222.155.1..."
oc exec network-test-diagnostic -n windows-non-prod -- traceroute -m 5 10.222.155.1 2>&1 | head -10
echo ""

# Summary
echo "=========================================="
echo "  Diagnostic Summary"
echo "=========================================="
echo ""
echo "Based on the results above:"
echo ""
echo "If VMs are PINGABLE from test pod:"
echo "  → VMs and OpenShift networking are OK"
echo "  → Problem is likely VPN routing or firewall"
echo "  → Action: Check VPN configuration for 10.132.104.0/22"
echo ""
echo "If VMs are NOT PINGABLE from test pod:"
echo "  → Problem is with VM network config or OpenShift"
echo "  → Action: Check VM console, verify Windows is running"
echo ""
echo "If gateway (10.132.104.1) is NOT reachable:"
echo "  → Networking infrastructure issue"
echo "  → Action: Check VPC routing and subnets"
echo ""
echo "If RDP port (3389) is closed:"
echo "  → Windows Firewall or RDP service issue"
echo "  → Action: Enable RDP in Windows VM"
echo ""

# Cleanup option
echo "=========================================="
echo ""
read -p "Delete test pod? (yes/no): " CLEANUP
if [ "$CLEANUP" = "yes" ]; then
    oc delete pod network-test-diagnostic -n windows-non-prod
    echo "✅ Test pod deleted"
fi
