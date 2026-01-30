# Hai máy / Hai terminal – OpenVPN

## 1. Máy LOCAL (laptop của bạn) – terminal trong project

- **Prompt:** `minhtri@minhtri:~/Downloads/ec2_bastion$`
- **Là:** Máy bạn, không phải SSH vào đâu cả.

**Trên máy LOCAL bạn làm:**

```bash
# Copy file client từ server về (chạy 1 lần)
scp -i terraform/ec2-bastion-vpn.pem admin@54.66.200.232:/home/admin/client1.ovpn .

# Bật VPN client (để nguyên terminal này chạy)
sudo openvpn --config client1.ovpn
# Đợi "Initialization Sequence Completed"
```

**Mở terminal mới (vẫn trên máy LOCAL):**

```bash
cd ~/Downloads/ec2_bastion
ping -c 3 10.0.3.225
ssh -i terraform/ec2-bastion-vpn.pem ec2-user@10.0.3.225
```

---

## 2. Máy VPN SERVER (EC2 54.66.200.232) – terminal “bên ngoài” / SSH

- **Prompt:** `root@minhtri:/etc/openvpn/easy-rsa#` hoặc `admin@ip-10-0-1-xxx`
- **Là:** Bạn đã SSH vào VPN server: `ssh -i terraform/ec2-bastion-vpn.pem admin@54.66.200.232`

**Trên VPN SERVER chỉ cần:**

- Chạy **OpenVPN server** (không chạy client):
  ```bash
  sudo systemctl start openvpn-server@server
  sudo systemctl status openvpn-server@server
  ```
- **Không** chạy `openvpn --config client1.ovpn` trên server. File `client1.ovpn` dùng trên **máy LOCAL** để nối vào server.

---

## Tóm tắt

| Việc | Chạy ở đâu |
|------|-------------|
| `scp ... client1.ovpn .` | **Máy LOCAL** |
| `sudo openvpn --config client1.ovpn` | **Máy LOCAL** |
| `ping 10.0.3.225` / `ssh ec2-user@10.0.3.225` | **Máy LOCAL** (sau khi VPN client đã “Initialization Sequence Completed”) |
| `systemctl start openvpn-server@server` | **VPN SERVER** (trong session SSH) |
