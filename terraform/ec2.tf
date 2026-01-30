data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_ami" "debian12" {
  most_recent = true
  owners      = ["136693071363"] # Debian official

  filter {
    name   = "name"
    values = ["debian-12-amd64-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "ssh" {
  key_name   = "${var.name_prefix}-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_file" "ssh_private_key_pem" {
  filename        = "${path.module}/${var.name_prefix}.pem"
  content         = tls_private_key.ssh.private_key_openssh
  file_permission = "0600"
}

resource "aws_security_group" "openvpn" {
  name   = "${var.name_prefix}-openvpn-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "OpenVPN UDP"
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "private_ec2" {
  name   = "${var.name_prefix}-private-ec2-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "SSH from VPN Server"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.openvpn.id]
  }

  # NEW: allow VPN client CIDR to SSH
  ingress {
    description = "Allow VPN clients to SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.8.0.0/24"]
  }

  ingress {
    description = "Allow from VPN and VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.openvpn_client_cidr, var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "openvpn" {
  ami                         = data.aws_ami.debian12.id
  instance_type               = var.openvpn_instance_type
  subnet_id                   = aws_subnet.public_subnet_a.id
  vpc_security_group_ids      = [aws_security_group.openvpn.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.ssh.key_name
  source_dest_check           = false # QUAN TRỌNG: Giữ nguyên cái này

  # User data mới: Chỉ cài đặt, không config (vì bạn muốn làm bằng tay/Ansible)
  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y openvpn easy-rsa
              EOF

  tags = { Name = "${var.name_prefix}-openvpn" }
}

resource "aws_eip" "openvpn" {
  domain   = "vpc"
  instance = aws_instance.openvpn.id

  tags = {
    Name = "${var.name_prefix}-openvpn-eip"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  # Reply path: private subnet -> VPN client subnet via OpenVPN instance.
  # Must be in this resource so Terraform does not remove it on apply.
  route {
    cidr_block           = var.openvpn_client_cidr
    network_interface_id = aws_instance.openvpn.primary_network_interface_id
  }

  tags = {
    Name = "${var.name_prefix}-private-rt"
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_subnet_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_instance" "private_ec2" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.private_instance_type
  subnet_id              = aws_subnet.private_subnet_a.id
  vpc_security_group_ids = [aws_security_group.private_ec2.id]
  key_name               = aws_key_pair.ssh.key_name

  tags = {
    Name = "${var.name_prefix}-private-ec2"
  }
}

