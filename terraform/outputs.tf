output "instance_id" {
  description = "The ID of the EC2 instance"
  value       = aws_instance.web.id
}

output "instance_public_ip" {
  description = "The public IP address of the EC2 instance"
  value       = aws_instance.web.public_ip
}

output "instance_public_dns" {
  description = "The public DNS name of the EC2 instance"
  value       = aws_instance.web.public_dns
}

output "website_url" {
  description = "Public URL to access the protected website"
  value       = "http://${aws_instance.web.public_ip}"
}

output "keycloak_admin_url" {
  description = "Keycloak Admin Web UI URL"
  value       = "http://${aws_instance.web.public_ip}:8085"
}

output "oauth_callback_url" {
  description = "OAuth 2.0 Redirect / Callback URL (Configure this in your OAuth Provider App settings)"
  value       = "http://${aws_instance.web.public_ip}/oauth2/callback"
}

output "ansible_run_command" {
  description = "Command to run Ansible playbook after Terraform provisions the instance"
  value       = "cd ../ansible && ansible-playbook -i inventory/hosts.ini playbook.yml"
}

output "security_group_id" {
  description = "The ID of the Security Group"
  value       = aws_security_group.web_ssh_sg.id
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "The ID of the Public Subnet"
  value       = aws_subnet.public.id
}
