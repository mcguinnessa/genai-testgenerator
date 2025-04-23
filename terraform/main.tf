####################################################################
#
# TERRAFORM FILE TO DEPLOY GENAI TEST GENERATOR
#
####################################################################
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }

  required_version = ">= 1.3.0"
}

provider "aws" {
  region = "eu-west-2"

}

####################################################################
#
# NETWORKING CONFIGURATION
#
####################################################################

#
# VPC
#
resource "aws_vpc" "gaitg_vpc" {
  cidr_block           = "172.31.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "gaitg-vpc"
  }
}

#
# Internet Gateway, allows outward access to the internet
#
resource "aws_internet_gateway" "gaitg_igw" {
  vpc_id = aws_vpc.gaitg_vpc.id

  tags = {
    Name = "gaitg-igw"
  }
}

#
# Routing Table, routes to IGW
#
resource "aws_route_table" "gaitg-rt" {
  vpc_id = aws_vpc.gaitg_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gaitg_igw.id
  }

  tags = {
    Name = "gaitg-rt"
  }
}

#
# Subnets
#
resource "aws_subnet" "subnet_a" {
  vpc_id                  =aws_vpc.gaitg_vpc.id
  availability_zone       = "eu-west-2a"
  cidr_block              = "172.31.16.0/20" 
  map_public_ip_on_launch = true
}

resource "aws_subnet" "subnet_b" {
  vpc_id                  =aws_vpc.gaitg_vpc.id
  availability_zone       = "eu-west-2b"
  cidr_block              = "172.31.32.0/20" 
  map_public_ip_on_launch = true
}

resource "aws_subnet" "subnet_c" {
  vpc_id                  =aws_vpc.gaitg_vpc.id
  availability_zone       = "eu-west-2c"
  cidr_block              = "172.31.0.0/20" 
  map_public_ip_on_launch = true
}

#
# Adds associations for each subnet
#
resource "aws_route_table_association" "subnet_a" {
  subnet_id      = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.gaitg-rt.id
}

resource "aws_route_table_association" "subnet_b" {
  subnet_id      = aws_subnet.subnet_b.id
  route_table_id = aws_route_table.gaitg-rt.id
}

resource "aws_route_table_association" "subnet_c" {
  subnet_id      = aws_subnet.subnet_c.id
  route_table_id = aws_route_table.gaitg-rt.id
}

#
# VPC Endpoint for access to Bedrock Runtime
#
resource "aws_vpc_endpoint" "bedrock_runtime" {
  vpc_id              = aws_vpc.gaitg_vpc.id
  service_name        = "com.amazonaws.eu-west-2.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id, aws_subnet.subnet_c.id]
  security_group_ids  = [aws_security_group.gaitg_app_sg.id, aws_security_group.gaitg_bedrock_access_sg.id]
  private_dns_enabled = true
}

#
# DNS - Private namespace
#
resource "aws_service_discovery_private_dns_namespace" "gaitg_local" {
  name        = "gaitg.local"
  description = "For the GenAI Test Generator application"
  vpc         = aws_vpc.gaitg_vpc.id

  tags = {
    Name = "gaitg.local"
  }
}

#
# DNS - Discovery service so Front End can refer to Back End by name
#
resource "aws_service_discovery_service" "gaitg_be" {
  name = "gaitg-be"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.gaitg_local.id
    dns_records {
      type = "A"
      ttl  = 15
    }
    routing_policy = "MULTIVALUE"
  }
  health_check_custom_config {
    failure_threshold = 1
  }
}
####################################################################
#
# SECURITY GROUPS
#
####################################################################

#
# Allows front end to connect to back end
#  - allows traffic from itself
#
resource "aws_security_group" "gaitg_app_sg" {
  name        = "genai-tc-app-sg"
  description = "Allows the fe and be to connect"
  egress      = [ 
    {
      cidr_blocks      = [
        "0.0.0.0/0",
      ]
      description      = null
      from_port        = 0
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "-1"
      security_groups  = []
      self             = false
      to_port          = 0
    },
  ]
  ingress  = [ 
    {
      cidr_blocks      = [ ]
      from_port       = 0
      to_port         = 0
      protocol        = "-1"
      self            = true
      description     = "Allow all traffic from itself"
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
    }
  ]
  vpc_id        = aws_vpc.gaitg_vpc.id
}

#
# Allows Load balancer to connect to front end
#  - allows incoming traffic from the internet on the HTTP port
#
resource "aws_security_group" "gaitg_webui_sg" {
  name        = "genai-ui-web-sg"
  description = "SG for front end for Gen AI TC UI"
  egress      = [
    {
      cidr_blocks      = [
        "0.0.0.0/0",
      ]
      description      = null
      from_port        = 0
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "-1"
      security_groups  = []
      self             = false
        to_port          = 0
    },
  ]
  ingress     = [
    {
      cidr_blocks      = [
        "0.0.0.0/0",
      ]
      description      = null
      from_port        = 80
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 80
    },
  ]
  vpc_id        = aws_vpc.gaitg_vpc.id
}

#
# Allows backend to connect to bedrock
#  - allows incoming traffic from the app security group on HTTPS port 
#
resource "aws_security_group" "gaitg_bedrock_access_sg" {
  name        = "genai-tc-bedrock-access-sg"
  description = "Allows access to bedrock"
  egress      = [
    {
       cidr_blocks      = [
         "0.0.0.0/0",
       ]
       description      = null
       from_port        = 0
       ipv6_cidr_blocks = []
       prefix_list_ids  = []
       protocol         = "-1"
       security_groups  = []
       self             = false
       to_port          = 0
    },
  ]
  ingress     = [
    {
      cidr_blocks      = []
      description      = null
      from_port        = 443
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = [
        aws_security_group.gaitg_app_sg.id,
      ]
      self             = false
      to_port          = 443
    },
  ]
  vpc_id        = aws_vpc.gaitg_vpc.id
}


####################################################################
#
# IAM 
#
####################################################################

#
# IAM Role for creating EC2 instances
#
resource "aws_iam_role" "ecs_instance_role" {
  name = "gaitg-ecs-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

#
# Attach policy to create containers
#
resource "aws_iam_role_policy_attachment" "ecs_attach" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

#
# Create profile to for the ECS Instances
#
resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "gaitg-ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

#
# IAM Roles for executing Tasks
#
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "gaitg-task-execution-role"
  assume_role_policy = jsonencode({
    Version = "2008-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

#
# Attach policy for task execution
#
resource "aws_iam_role_policy_attachment" "ecs_attach_execution" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

####################################################################
#
# Capacity Reservations / Auto Scaling Groups 
#
####################################################################

#
# Launch Template for EC2 instances in ASG
#
resource "aws_launch_template" "gaitg_ecs_lt" {
  name_prefix   = "gaitg-ecs-lt-"
  image_id      = data.aws_ami.ecs.id
  instance_type = "t2.micro"

  user_data = base64encode(<<EOF
#!/bin/bash
echo ECS_CLUSTER=genai-web-cluster >> /etc/ecs/ecs.config
EOF
  )

  lifecycle {
    create_before_destroy = true
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }
}

#
# Amazon Linux Image
#
data "aws_ami" "ecs" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

#
# Auto Scaling Group (ASG)
#
resource "aws_autoscaling_group" "gaitg_asg" {
  name                      = "gaitg-ecs-asg"
  max_size                  = 2
  min_size                  = 0 
  desired_capacity          = 2 
  protect_from_scale_in     = true
  vpc_zone_identifier       = [
    aws_subnet.subnet_a.id,
    aws_subnet.subnet_b.id,
    aws_subnet.subnet_c.id
  ]
  launch_template {
    id      = aws_launch_template.gaitg_ecs_lt.id
    #version = "$Latest"
    version = aws_launch_template.gaitg_ecs_lt.latest_version
  }
  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }
}

#
# Capacity Provider
#
resource "aws_ecs_capacity_provider" "gaitg_cp" {
  name = "gaitg-cp"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.gaitg_asg.arn
    managed_termination_protection = "ENABLED"

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 100
      instance_warmup_period    = 60
    }
  }
}

####################################################################
#
# Cluster for application
#
####################################################################

#
# Cluster
#
resource "aws_ecs_cluster" "gaitg_cluster" {
  name = "gaitg-cluster"
}

#
# Associate cluster with Auto Scaling Group
#
resource "aws_ecs_cluster_capacity_providers" "gaitg_cp_assoc" {
  cluster_name         = aws_ecs_cluster.gaitg_cluster.name
  capacity_providers   = [aws_ecs_capacity_provider.gaitg_cp.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.gaitg_cp.name
    weight            = 1
    base              = 0
  }
}

####################################################################
#
# LOAD BALANCER
#
####################################################################
resource "aws_lb" "gaitg_lb" {
  name               = "gaitg-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.gaitg_app_sg.id, aws_security_group.gaitg_webui_sg.id]
  subnets            = [
    aws_subnet.subnet_a.id,
    aws_subnet.subnet_b.id,
    aws_subnet.subnet_c.id
  ]
  ip_address_type = "ipv4"

  tags = {
    Name = "gaitg-lb"
  }
}

#
# Target Group to FE
#
resource "aws_lb_target_group" "gaitg_fe_tg" {
  name                              = "gaitg-fe-tg"
  port                              = 80
  protocol                          = "HTTP"
  vpc_id                            = aws_vpc.gaitg_vpc.id
  target_type                       = "ip"
  deregistration_delay              = 300
  load_balancing_algorithm_type     = "round_robin"
  load_balancing_cross_zone_enabled = "use_load_balancer_configuration"
  slow_start                        = 0

  health_check {
    enabled             = true
    healthy_threshold   = 5
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  stickiness {
    cookie_duration = 86400
    enabled         = false
    type            = "lb_cookie"
  }

  target_group_health {
    dns_failover {
      minimum_healthy_targets_count      = 1
      minimum_healthy_targets_percentage = "off"
    }
    unhealthy_state_routing {
      minimum_healthy_targets_count      = 1
      minimum_healthy_targets_percentage = "off"
    }
  }
  tags = {}
}

#
# Listener
#
resource "aws_lb_listener" "gaitg_fe_listener" {
  load_balancer_arn = aws_lb.gaitg_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gaitg_fe_tg.arn
  }
}


####################################################################
#
# BACK END
#
####################################################################

#
# Back End Task Definition
#
resource "aws_ecs_task_definition" "gaitg_be_td" {
  family                   = "gaitg-be-td"
  requires_compatibilities = ["EC2"]
  network_mode            = "awsvpc"
  cpu                     = "1024"
  memory                  = "512"
  execution_role_arn      = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name               = "gaitg-be-task-container"
      image              = "mcguinnessa/genai-tc-be:latest"
      cpu                = 512
      memoryReservation  = 512
      essential          = true

      portMappings = [
        {
          name          = "rest"
          containerPort = 5000
          hostPort      = 5000
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]

      environment = [
        {
          name  = "AWS_ACCESS_KEY_ID"
          value = var.aws_access_key_id  
        },
        {
          name  = "AWS_SECRET_ACCESS_KEY"
          value = var.aws_secret_access_key 
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/gaitg-be-task"
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
          mode                  = "non-blocking"
          awslogs-create-group  = "true"
          max-buffer-size       = "25m"
        }
      }
    }
  ])

  volume {
    name = "root"
    host_path  = "/"
  }

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }
}


#
# Back End Service
#
resource "aws_ecs_service" "gaitg_be_service" {
  cluster                            = aws_ecs_cluster.gaitg_cluster.arn
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  desired_count                      = 1
  name                               = "gaitg-be"
  task_definition                    = aws_ecs_task_definition.gaitg_be_td.arn

  capacity_provider_strategy {
    base              = 0
    capacity_provider = aws_ecs_capacity_provider.gaitg_cp.name
    weight            = 1
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  network_configuration {
    assign_public_ip = false
    security_groups  = [
      aws_security_group.gaitg_app_sg.id,
    ]
    subnets          = [
      aws_subnet.subnet_a.id,
      aws_subnet.subnet_b.id,
      aws_subnet.subnet_c.id
    ]
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.gaitg_be.arn
  }
}


####################################################################
#
# FRONT END
#
####################################################################

#
# Front End Task Definition
#
resource "aws_ecs_task_definition" "gaitg_fe_td" {
  family                   = "gaitg-fe-td"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = "512"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name                  = "gaitg-fe-task-container"
      image                 = "mcguinnessa/genai-tc-web:latest"
      cpu                   = 512
      memoryReservation     = 512
      essential             = true
      portMappings = [
        {
          name          = "gaitg-fe-task-container-7860-tcp"
          containerPort = 7860
          hostPort      = 7860
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]
      environment = [
        {
          name  = "UI_USER"
          value = "capg"
        },
        {
          name  = "GRADIO_ANALYTICS_ENABLED"
          value = "false"
        },
        {
          name  = "API_KEY"
          value = var.api_key
        },
        {
          name  = "UI_PASSWORD"
          value = var.ui_password
        },
        {
          name  = "GE_BACKEND_URL"
          value = "wss://ws.generative.engine.capgemini.com/"
        },
        {
          name  = "SD_BACKEND_URL"
          value = "http://gaitg-be.gaitg.local:5000"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/gaitg-fe"
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
          awslogs-create-group  = "true"
          mode                  = "non-blocking"
          max-buffer-size       = "25m"
        }
      }
    }
  ])
}

#
# Front End Service
#
resource "aws_ecs_service" "gaitg_fe_service" {
  availability_zone_rebalancing      = "ENABLED"
  cluster                            = aws_ecs_cluster.gaitg_cluster.arn
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  desired_count                      = 1
  enable_ecs_managed_tags            = true
  enable_execute_command             = false
  health_check_grace_period_seconds  = 0
  launch_type                        = null
  name                               = "gaitg-fe"
  platform_version                   = null
  propagate_tags                     = "NONE"
  scheduling_strategy                = "REPLICA"
  tags                               = {}
  tags_all                           = {}
  task_definition                    = aws_ecs_task_definition.gaitg_fe_td.arn
  triggers                           = {}

  capacity_provider_strategy {
    base              = 0
    capacity_provider = aws_ecs_capacity_provider.gaitg_cp.name
    weight            = 1
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  load_balancer {
    container_name   = "gaitg-fe-task-container"
    container_port   = 7860
    elb_name         = null
    target_group_arn = aws_lb_target_group.gaitg_fe_tg.arn
  }

  network_configuration {
    assign_public_ip = false
    security_groups  = [
      aws_security_group.gaitg_app_sg.id,
    ]
    subnets          = [
      aws_subnet.subnet_a.id,
      aws_subnet.subnet_b.id,
      aws_subnet.subnet_c.id
    ]
  }

  ordered_placement_strategy {
    field = "attribute:ecs.availability-zone"
    type  = "spread"
  }
  ordered_placement_strategy {
    field = "instanceId"
    type  = "spread"
  }
}

