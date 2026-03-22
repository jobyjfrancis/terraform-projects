provider "aws" {
  region = var.aws_region
}

variable "aws_region" {}
variable "container_image" {}

resource "aws_iam_role" "edutech_ecs_service_role" {
  name = "EduTech-ECS-Service-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "edutech_ecs_service_role_policy" {
  role       = aws_iam_role.edutech_ecs_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}

resource "aws_iam_role" "edutech_ecs_task_role" {
  name = "EduTech-ECS-Task-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "edutech_ecs_task_role_policy_1" {
  role       = aws_iam_role.edutech_ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "edutech_ecs_task_role_policy_2" {
  role       = aws_iam_role.edutech_ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

data "aws_availability_zones" "available" {}

module "edutech_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  name = "EduTech-VPC"
  cidr = "10.0.0.0/16"

  azs            = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_nat_gateway   = false
  enable_vpn_gateway   = false
  single_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "EduTech-VPC"
  }
}

resource "aws_security_group" "edutech_alb_sg" {
  name        = "EduTech-ALB-SG"
  description = "Allow HTTP and HTTPS from anywhere"
  vpc_id      = module.edutech_vpc.vpc_id

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "EduTech-ALB-SG"
  }
}

resource "aws_security_group" "edutech_container_sg" {
  name        = "EduTech-Container-SG"
  description = "Allow port 3000 from ALB SG"
  vpc_id      = module.edutech_vpc.vpc_id

  ingress {
    description     = "Allow 3000 from ALB SG"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.edutech_alb_sg.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "EduTech-Container-SG"
  }
}

resource "aws_ecr_repository" "edutech_lms_frontend" {
  name = "edutech-lms-frontend"
  image_tag_mutability = "MUTABLE"
  tags = {
    Name = "edutech-lms-frontend"
  }
}

resource "aws_lb" "edutech_lms_alb" {
  name               = "EduTech-LMS-ALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.edutech_alb_sg.id]
  subnets            = module.edutech_vpc.public_subnets
  ip_address_type    = "ipv4"
  tags = {
    Name = "EduTech-LMS-ALB"
  }
}

resource "aws_lb_target_group" "edutech_lms_tg" {
  name        = "EduTech-LMS-TG"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.edutech_vpc.vpc_id
  ip_address_type = "ipv4"
  health_check {
    protocol = "HTTP"
    path     = "/"
  }
  tags = {
    Name = "EduTech-LMS-TG"
  }
}

resource "aws_lb_listener" "edutech_lms_http" {
  load_balancer_arn = aws_lb.edutech_lms_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.edutech_lms_tg.arn
  }
}

resource "aws_ecs_cluster" "edutech_lms_cluster" {
  name = "EduTech-LMS-Cluster"
  tags = {
    Name = "EduTech-LMS-Cluster"
  }
}

resource "aws_ecs_cluster_capacity_providers" "edutech_lms_cluster_capacity_providers" {
  cluster_name = aws_ecs_cluster.edutech_lms_cluster.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

resource "aws_ecs_task_definition" "edutech_lms_task_def" {
  family                   = "EduTech-Task-Def"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512" # 0.5 vCPU
  memory                   = "1024" # 1 GB
  execution_role_arn       = aws_iam_role.edutech_ecs_task_role.arn
  task_role_arn            = aws_iam_role.edutech_ecs_task_role.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "lms-frontend"
      image     = var.container_image
      cpu       = 256 # 0.25 vCPU
      memory    = 512 # 0.5 GB
      essential = true
      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]
    }
  ])
  tags = {
    Name = "EduTech-LMS-Task-Def"
  }
}

resource "aws_ecs_service" "edutech_lms_service" {
  name            = "EduTech-LMS-Service"
  cluster         = aws_ecs_cluster.edutech_lms_cluster.id
  task_definition = aws_ecs_task_definition.edutech_lms_task_def.arn
  launch_type     = "FARGATE"
  platform_version = "LATEST"
  scheduling_strategy = "REPLICA"
  desired_count   = 1
  network_configuration {
    security_groups = [aws_security_group.edutech_container_sg.id]
    subnets         = module.edutech_vpc.public_subnets
    assign_public_ip = true
    }
  load_balancer {
    target_group_arn = aws_lb_target_group.edutech_lms_tg.arn
    container_name   = "lms-frontend"
    container_port   = 3000
  }
  depends_on = [
    aws_iam_role_policy_attachment.edutech_ecs_service_role_policy
  ]
}



