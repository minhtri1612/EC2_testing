output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public_subnet_a.id
}

output "private_subnet_id" {
  value = aws_subnet.private_subnet_a.id
}

output "openvpn_eip" {
  value = aws_eip.openvpn.public_ip
}

output "openvpn_private_ip" {
  value = aws_instance.openvpn.private_ip
}

output "private_ec2_private_ip" {
  value = aws_instance.private_ec2.private_ip
}

output "ssh_private_key_path" {
  value = local_file.ssh_private_key_pem.filename
}

