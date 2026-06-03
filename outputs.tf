output "instance_ids" {
  description = "The IDs of the EC2 instances"
  value       = aws_instance.web_server[*].id
}

output "instance_private_ips" {
  description = "Private IP addresses of the instances"
  value       = aws_instance.web_server[*].private_ip
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.web_sg.id
}

output "region" {
  description = "AWS region"
  value       = var.aws_region
}

output "instance_names" {
  description = "Name of the EC2 instance (from Name tag)"
  value       = aws_instance.web_server[0].tags["Name"]
}
