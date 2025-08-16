data "aws_ami" "amazonlinux" {
  most_recent = true
  region      = "ap-southeast-2"
  filter {
    name   = "name"
    values = ["al2023-ami-2023.8.20250808.1-kernel-6.1-x86_64"]

  }

  owners = ["137112412989"] # Amazon
}

data "aws_vpc" "default" {
  region  = "ap-southeast-2"
  default = true
}

resource "aws_security_group" "web_sg" {
  region      = "ap-southeast-2"
  name        = "web-sg"
  description = "Allow HTTP inbound traffic and all outbound traffic"
  vpc_id      = data.aws_vpc.default.id
  tags = {
    Name = "web-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {
  region            = "ap-southeast-2"
  security_group_id = aws_security_group.web_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "allow_https_ipv4" {
  region            = "ap-southeast-2"
  security_group_id = aws_security_group.web_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  region            = "ap-southeast-2"
  security_group_id = aws_security_group.web_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_instance" "web_server" {
  region                      = "ap-southeast-2"
  ami                         = data.aws_ami.amazonlinux.id
  instance_type               = "t3.micro"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.web_sg.id]

  tags = {
    Name = "ap-southeast-2-server"
  }

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    # updated script to make it work with Amazon Linux 2023
    CHECK_IMDSV1_ENABLED=$(curl -s -o /dev/null -w "%"{http_code}"" http://169.254.169.254/latest/meta-data/)
    if [[ "$CHECK_IMDSV1_ENABLED" -eq 200 ]]
    then
        EC2_AVAIL_ZONE="$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"
    else
        EC2_AVAIL_ZONE="$(TOKEN=`curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"` && curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)"
    fi
    echo "<h1>Hello world from $(hostname -f) in AZ $EC2_AVAIL_ZONE </h1>" > /var/www/html/index.html
   EOF 
}
