provider "aws" {
  region = "ap-southeast-2"
}

data "aws_ami" "amazonlinux" {
  most_recent = true
  owners      = ["137112412989"] # Amazon

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-*-x86_64"]
  }
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_key_pair" "my_key" {
  key_name   = "my-aws-key"
  public_key = file("~/.ssh/id_rsa_aws.pub")
}

resource "aws_security_group" "web_sg" {
  name        = "web-sg"
  description = "Allow HTTP inbound traffic and all outbound traffic"
  vpc_id      = data.aws_vpc.default.id
  tags = {
    Name = "web-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {

  security_group_id = aws_security_group.web_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "allow_https_ipv4" {
  security_group_id = aws_security_group.web_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh" {
  security_group_id = aws_security_group.web_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.web_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_instance" "web_server" {
  ami                         = data.aws_ami.amazonlinux.id
  instance_type               = "t3.micro"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  key_name                    = aws_key_pair.my_key.key_name

  tags = {
    Name = "my-web-server"
  }

  # user_data = <<-EOF
  #   #!/bin/bash
  #   # Use this for your user data (script from top to bottom)
  #   # install httpd (Linux 2 version)
  #   yum update -y
  #   yum install -y httpd
  #   systemctl start httpd
  #   systemctl enable httpd
  #   echo "<h1>Hello World from $(hostname -f)</h1>" > /var/www/html/index.html
  #  EOF 
  user_data = <<-EOF
    #!/bin/bash
    # Use this for your user data (script from top to bottom)
    # install docker
    sudo yum update -y
    sudo yum install -y docker
    sudo service docker start
    sudo usermod -aG docker $USER
    EOF
}

output "ec2_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.web_server.public_ip
}
