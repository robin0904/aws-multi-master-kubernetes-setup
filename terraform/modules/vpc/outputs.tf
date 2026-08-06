output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the created VPC"
}

output "vpc_cidr_block" {
  value       = aws_vpc.main.cidr_block
  description = "The CIDR block of the VPC"
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "List of IDs of the public subnets"
}

output "private_subnet_ids" {
  value       = aws_subnet.private[*].id
  description = "List of IDs of the private subnets"
}

output "nat_gateway_ips" {
  value       = aws_eip.nat[*].public_ip
  description = "Public IP addresses of NAT Gateways"
}
