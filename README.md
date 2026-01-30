# EC2 Bastion with OpenVPN Community Edition

## 🏗️ Kiến trúc

- **OpenVPN Server**: Community Edition (free, open-source)
- **VPN Network**: 10.8.0.0/24
- **VPC**: 10.0.0.0/16
- **Private EC2**: Chỉ truy cập được qua VPN

## 🚀 Deploy

```bash
./deploy.sh
```

## 📝 Sau khi deploy

### 1. SSH vào OpenVPN server
```bash
ssh -i terraform/ec2-bastion-vpn.pem admin@<OPENVPN_IP>
```

### 2. Tạo client certificate
```bash
cd /etc/openvpn/easy-rsa
sudo ./easyrsa gen-req client1 nopass
sudo echo "yes" | ./easyrsa sign-req client client1
```

### 3. Tạo client config file
```bash
sudo cat > ~/client1.ovpn << 'EOF'
client
dev tun
proto udp
remote <OPENVPN_PUBLIC_IP> 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
key-direction 1
verb 3
EOF
```

### 4. Thêm certificates vào config
```bash
echo '<ca>' >> ~/client1.ovpn
sudo cat /etc/openvpn/server/ca.crt >> ~/client1.ovpn
echo '</ca>' >> ~/client1.ovpn

echo '<cert>' >> ~/client1.ovpn
sudo cat /etc/openvpn/easy-rsa/pki/issued/client1.crt >> ~/client1.ovpn
echo '</cert>' >> ~/client1.ovpn

echo '<key>' >> ~/client1.ovpn
sudo cat /etc/openvpn/easy-rsa/pki/private/client1.key >> ~/client1.ovpn
echo '</key>' >> ~/client1.ovpn

echo '<tls-auth>' >> ~/client1.ovpn
sudo cat /etc/openvpn/server/ta.key >> ~/client1.ovpn
echo '</tls-auth>' >> ~/client1.ovpn
```

### 5. Download file về máy
```bash
# Trên máy local
scp -i terraform/ec2-bastion-vpn.pem admin@<IP>:~/client1.ovpn .
```

### 6. Kết nối VPN
```bash
sudo openvpn --config client1.ovpn
```

### 7. Truy cập Private EC2
```bash
# Sau khi connect VPN
ssh -i terraform/ec2-bastion-vpn.pem ec2-user@<PRIVATE_EC2_IP>
```

## 🗑️ Xóa hết
```bash
cd terraform && terraform destroy -auto-approve
```

## 🔒 Bảo mật

- ✅ Private EC2 không có public IP
- ✅ OpenVPN dùng TLS + AES-256-GCM
- ✅ Certificate-based authentication
- ✅ IP forwarding + NAT configured
# EC2_testing
