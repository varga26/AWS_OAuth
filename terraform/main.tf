resource "aws_key_pair" "deployer" {
  count      = var.ssh_public_key != "" ? 1 : 0
  key_name   = "${var.environment}-deployer-key"
  public_key = var.ssh_public_key
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web_ssh_sg.id]
  key_name               = var.ssh_public_key != "" ? aws_key_pair.deployer[0].key_name : null

  tags = {
    Name = var.instance_name
  }
}

resource "local_file" "ansible_inventory" {
  content = <<-EOT
[webservers]
webserver1 ansible_host=${aws_instance.web.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/new-aws-key.pem

[webservers:vars]
ansible_python_interpreter=/usr/bin/python3
EOT

  filename = "${path.module}/../ansible/inventory/hosts.ini"
}
