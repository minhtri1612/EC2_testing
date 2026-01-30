#!/bin/bash
# =============================================================================
# deploy.sh — Flow tổng quát:
#   1. Terraform: tạo VPC, EC2 (OpenVPN + private), NAT, route, key .pem
#   2. Lấy IP từ Terraform output
#   3. Ghi Ansible inventory với IP VPN server
#   4. Ansible: cấu hình OpenVPN server, tạo client1.ovpn trên server
#   5. SCP client1.ovpn từ server về máy local (project root)
#   6. Cài systemd unit + start VPN client nền (không cần giữ terminal)
# =============================================================================
set -e

echo "=========================================="
echo "🚀 Deploying EC2 Bastion with OpenVPN"
echo "=========================================="

# -----------------------------------------------------------------------------
# [1/6] Terraform: init + apply
#   admin_cidr: mặc định 0.0.0.0/0 (SSH từ mọi nơi, tránh timeout khi IP/curl không khớp)
#   Thu hẹp: ADMIN_CIDR=1.2.3.4/32 ./deploy.sh
# -----------------------------------------------------------------------------
echo ""
echo "📦 [1/6] Running Terraform..."
cd terraform
ADMIN_CIDR="${ADMIN_CIDR:-0.0.0.0/0}"
echo "   admin_cidr (SSH): $ADMIN_CIDR"
terraform init -upgrade
terraform apply -auto-approve -var "admin_cidr=${ADMIN_CIDR}"

# -----------------------------------------------------------------------------
# [2/6] Lấy IP từ Terraform output
#   - openvpn_eip: IP public của VPN server (để client kết nối + Ansible SSH)
#   - private_ec2_private_ip: IP private của EC2 trong VPC (để ping/SSH sau VPN)
# -----------------------------------------------------------------------------
echo ""
echo "📋 [2/6] Getting OpenVPN IP..."
OPENVPN_IP=$(terraform output -raw openvpn_eip)
PRIVATE_IP=$(terraform output -raw private_ec2_private_ip)

echo "   OpenVPN IP: $OPENVPN_IP"
echo "   Private EC2: $PRIVATE_IP"

# -----------------------------------------------------------------------------
# [3/6] Dynamic inventory: IP từ Terraform, không ghi vào file (tránh hardcode)
#   Connection vars trong ansible/group_vars/vpn_server.yml
# -----------------------------------------------------------------------------
echo ""
echo "📝 [3/6] Using dynamic inventory (IP from Terraform)..."
cd ../ansible
echo "   ✅ Inventory: vpn_server,$OPENVPN_IP (no IP in file)"

# Đợi SSH mở (EC2 boot + user_data apt) — retry tối đa 4 phút
echo ""
echo "⏳ Waiting for SSH on $OPENVPN_IP (max 4 min)..."
for i in $(seq 1 24); do
  if ssh -i ../terraform/ec2-bastion-vpn.pem -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes "admin@${OPENVPN_IP}" "exit" 2>/dev/null; then
    echo "   ✅ SSH ready after ~$((i * 10))s"
    break
  fi
  [ "$i" -eq 24 ] && { echo "   ❌ SSH timeout after 4 min. Kiểm tra security group / IP."; exit 1; }
  sleep 10
done
sleep 5

# -----------------------------------------------------------------------------
# [4/6] Ansible playbook (retry 3 lần nếu unreachable — tránh timeout lúc mới SSH xong)
#   - Cấu hình OpenVPN server (cert, key, route, iptables FORWARD)
#   - Tạo client certificate "client1", build file client1.ovpn trên server
#     với remote = openvpn_public_ip (truyền qua -e) để client biết địa chỉ server
#   File client1.ovpn nằm tại /home/admin/client1.ovpn trên VPN server
# -----------------------------------------------------------------------------
echo ""
echo "🔧 [4/6] Configuring OpenVPN with Ansible..."
INV_FILE=$(mktemp)
printf '[vpn_server]\n%s\n' "$OPENVPN_IP" > "$INV_FILE"
for attempt in 1 2 3; do
  if ansible-playbook -i "$INV_FILE" setup_vpn.yml -e "openvpn_public_ip=$OPENVPN_IP"; then
    break
  fi
  [ "$attempt" -eq 3 ] && { rm -f "$INV_FILE"; exit 1; }
  echo "   ⚠ Ansible unreachable, retry in 15s ($attempt/3)..."
  sleep 15
done
rm -f "$INV_FILE"

# -----------------------------------------------------------------------------
# [5/6] File .ovpn đã được Ansible fetch về project root (cùng SSH, không cần SCP riêng)
# -----------------------------------------------------------------------------
FIRST_VPN_USER="${FIRST_VPN_USER:-minhtri}"
echo ""
echo "📥 [5/6] .ovpn files fetched by Ansible to project root..."
cd ..
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$PROJECT_ROOT/${FIRST_VPN_USER}.ovpn" ]; then
  echo "   ⚠ ${FIRST_VPN_USER}.ovpn not found, trying scp fallback..."
  scp -i terraform/ec2-bastion-vpn.pem -o StrictHostKeyChecking=no -o ConnectTimeout=15 "admin@${OPENVPN_IP}:/home/admin/${FIRST_VPN_USER}.ovpn" "$PROJECT_ROOT/${FIRST_VPN_USER}.ovpn" || true
fi
[ -f "$PROJECT_ROOT/${FIRST_VPN_USER}.ovpn" ] && echo "   ✅ ${FIRST_VPN_USER}.ovpn ready" || echo "   ❌ No .ovpn file (add admin_cidr=0.0.0.0/0 or retry)"

# -----------------------------------------------------------------------------
# [6/6] Systemd: cài unit + start VPN client nền (chỉ khi đã có .ovpn)
# -----------------------------------------------------------------------------
echo ""
if [ -f "$PROJECT_ROOT/${FIRST_VPN_USER}.ovpn" ]; then
  echo "🔄 [6/6] Installing systemd unit and starting VPN client in background..."
  UNIT_PATH="/etc/systemd/system/openvpn-client@.service"
  sudo tee "$UNIT_PATH" > /dev/null << EOF
[Unit]
Description=OpenVPN client %i
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/openvpn --config $PROJECT_ROOT/${FIRST_VPN_USER}.ovpn
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl restart "openvpn-client@${FIRST_VPN_USER}"
  echo "   ✅ openvpn-client@${FIRST_VPN_USER} restarted (đọc config mới)"
else
  echo "🔄 [6/6] Skipping systemd (no .ovpn file). Chạy lại khi đã có file hoặc mở admin_cidr."
fi

# Done
echo ""
echo "=========================================="
echo "✅ Deployment Complete!"
echo "=========================================="
echo ""
echo "🔐 OpenVPN Server: $OPENVPN_IP  |  Private EC2: $PRIVATE_IP"
echo ""
echo "📌 VPN client đã chạy nền (systemd). Chờ vài giây rồi:"
echo "   ping -c 3 $PRIVATE_IP && ssh -i terraform/ec2-bastion-vpn.pem ec2-user@$PRIVATE_IP"
echo ""
echo "   Nếu cần restart VPN: sudo systemctl restart openvpn-client@${FIRST_VPN_USER}"
echo "   (Dùng user khác: FIRST_VPN_USER=sep_tong ./deploy.sh)"
echo ""
