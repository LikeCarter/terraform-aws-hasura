output "vpc" {
  value = aws_vpc.okatee
}

output "private_subnets" {
  value = aws_subnet.okatee_private
}

output "public_subnets" {
  value = aws_subnet.okatee_public
}

output "ecs_security_group" {
  value = aws_security_group.okatee_ecs
}
