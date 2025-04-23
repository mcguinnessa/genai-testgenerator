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


#IAM role for creating instances
resource "aws_iam_role" "ecs_instance_role" {
  name = "ecsInstanceRole"
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

resource "aws_iam_role_policy_attachment" "ecs_attach" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecsInstanceProfile"
  role = aws_iam_role.ecs_instance_role.name
}


#IAM role for executing tasks in ECS
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole2"
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

resource "aws_iam_role_policy_attachment" "ecs_attach_execution" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}




# Launch Template
resource "aws_launch_template" "ecs_lt" {
  name_prefix   = "ecs-lt-"
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

data "aws_ami" "ecs" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

#Auto Scaling Group
resource "aws_autoscaling_group" "ecs_asg" {
  name                      = "ecs-asg-genai"
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
    id      = aws_launch_template.ecs_lt.id
    #version = "$Latest"
    version = aws_launch_template.ecs_lt.latest_version
  }
  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }
}

# Capacity Provider
resource "aws_ecs_capacity_provider" "genai_cp" {
  name = "genai-cp"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_asg.arn
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




# Cluster
resource "aws_ecs_cluster" "genai" {
  name = "genai-web-cluster"
}

# Associate cluster with ASG
resource "aws_ecs_cluster_capacity_providers" "genai_cp_assoc" {
  cluster_name         = aws_ecs_cluster.genai.name
  capacity_providers   = [aws_ecs_capacity_provider.genai_cp.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.genai_cp.name
    weight            = 1
    base              = 0
  }
}

resource "aws_lb" "genai_tc_lb" {
  name               = "genai-tc-lb"
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
    Name = "genai-tc-lb"
  }
}


resource "aws_lb_target_group" "existing_genai_fe_target" {
  name                              = "ecs-genai--genai-tc-fe-alb"
  port                              = 80
  protocol                          = "HTTP"
#  vpc_id                            = "vpc-04fae15b271dcd9a6"
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


resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.genai_tc_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    #target_group_arn = aws_lb_target_group.genai_fe_target.arn
    target_group_arn = aws_lb_target_group.existing_genai_fe_target.arn
  }
}

#Task for backend process

resource "aws_ecs_task_definition" "genai_tc_be_td" {
  family                   = "genai-tc-be-td"
  requires_compatibilities = ["EC2"]
  network_mode            = "awsvpc"
  cpu                     = "1024"
  memory                  = "512"
  #execution_role_arn      = "arn:aws:iam::637423404396:role/ecsTaskExecutionRole"
  execution_role_arn      = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name               = "genai-be-task-container"
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
          value = var.aws_access_key_id  # Use a variable or secret
        },
        {
          name  = "AWS_SECRET_ACCESS_KEY"
          value = var.aws_secret_access_key  # Use a variable or secret
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/genai-be-task"
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


# Service for back end process
resource "aws_ecs_service" "gaitg_be_service" {
#    availability_zone_rebalancing      = "ENABLED"
#    cluster                            = "arn:aws:ecs:eu-west-2:637423404396:cluster/genai-web-cluster"
    cluster                            = aws_ecs_cluster.genai.arn
    deployment_maximum_percent         = 200
    deployment_minimum_healthy_percent = 100
    desired_count                      = 1
    name                               = "genai-tc-be"
    task_definition                    = aws_ecs_task_definition.genai_tc_be_td.arn

    capacity_provider_strategy {
        base              = 0
        #capacity_provider = "Infra-ECS-Cluster-genai-web-cluster-96d1f640-EC2CapacityProvider-XFtKLZVEjtAa"
        capacity_provider = aws_ecs_capacity_provider.genai_cp.name
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
#            "sg-04814b3dd0087fbae",
        security_groups  = [
#            "sg-028fbf6c4c46ef684",
            aws_security_group.gaitg_app_sg.id,
        ]
        subnets          = [
            aws_subnet.subnet_a.id,
            aws_subnet.subnet_b.id,
           aws_subnet.subnet_c.id
#            "subnet-044ed30457d097ec8",
#            "subnet-048f197fce1668d85",
#            "subnet-093f92443cb5b3bf5",
        ]
    }

    service_registries {
##        registry_arn   = "arn:aws:servicediscovery:eu-west-2:637423404396:service/srv-wm4okxwjezyqkv7o"
        registry_arn   = aws_service_discovery_service.genai_tc_be.arn
    }


}


# Task definition for Front End
resource "aws_ecs_task_definition" "genai_tc_fe_td" {
  family                   = "genai-tc-fe-td"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = "512"
  memory                   = "512"
  #execution_role_arn      = "arn:aws:iam::637423404396:role/ecsTaskExecutionRole"
  execution_role_arn      = aws_iam_role.ecs_task_execution_role.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name                  = "genai-fe-task-container"
      image                 = "mcguinnessa/genai-tc-web:latest"
      cpu                   = 512
      memoryReservation     = 512
      essential             = true
      portMappings = [
        {
          name          = "genai-fe-task-container-7860-tcp"
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
          value = "http://genai-tc-be.genai.local:5000"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/genai-tc-fe"
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


resource "aws_ecs_service" "gaitg_fe_service" {
    availability_zone_rebalancing      = "ENABLED"
    cluster                            = aws_ecs_cluster.genai.arn
    deployment_maximum_percent         = 200
    deployment_minimum_healthy_percent = 100
    desired_count                      = 1
    enable_ecs_managed_tags            = true
    enable_execute_command             = false
    health_check_grace_period_seconds  = 0
    #id                                 = "arn:aws:ecs:eu-west-2:637423404396:service/genai-web-cluster/genai-tc-fe-alb"
    launch_type                        = null
    name                               = "genai-tc-fe-alb"
    platform_version                   = null
    propagate_tags                     = "NONE"
    scheduling_strategy                = "REPLICA"
    tags                               = {}
    tags_all                           = {}
    task_definition                    = aws_ecs_task_definition.genai_tc_fe_td.arn
    triggers                           = {}

    capacity_provider_strategy {
        base              = 0
        #capacity_provider = "Infra-ECS-Cluster-genai-web-cluster-96d1f640-EC2CapacityProvider-XFtKLZVEjtAa"
        capacity_provider = aws_ecs_capacity_provider.genai_cp.name
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
        container_name   = "genai-fe-task-container"
        container_port   = 7860
        elb_name         = null
        #target_group_arn = "arn:aws:elasticloadbalancing:eu-west-2:637423404396:targetgroup/ecs-genai--genai-tc-fe-alb/87135871de8a1a63"
        target_group_arn = aws_lb_target_group.existing_genai_fe_target.arn
    }

    network_configuration {
        assign_public_ip = false
        security_groups  = [
#            "sg-028fbf6c4c46ef684",
            aws_security_group.gaitg_app_sg.id,
#            "sg-04814b3dd0087fbae",
        ]
        subnets          = [
             aws_subnet.subnet_a.id,
             aws_subnet.subnet_b.id,
             aws_subnet.subnet_c.id
#            "subnet-044ed30457d097ec8",
#            "subnet-048f197fce1668d85",
#            "subnet-093f92443cb5b3bf5",
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

resource "aws_vpc_endpoint" "bedrock_runtime" {
#  vpc_id            = "vpc-04fae15b271dcd9a6"
  vpc_id            = aws_vpc.gaitg_vpc.id
  service_name      = "com.amazonaws.eu-west-2.bedrock-runtime"
  vpc_endpoint_type = "Interface"
    #subnet_ids        = ["subnet-044ed30457d097ec8", "subnet-048f197fce1668d85"] 
    subnet_ids        = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id, aws_subnet.subnet_c.id]

  #security_group_ids = ["sg-04814b3dd0087fbae", "sg-0351278568261466e"]
  security_group_ids = [aws_security_group.gaitg_app_sg.id, aws_security_group.gaitg_bedrock_access_sg.id]

  private_dns_enabled = true
}

resource "aws_service_discovery_private_dns_namespace" "genai_local" {
  name        = "genai.local"
  description = "For the genai tc application"
#  vpc         = "vpc-04fae15b271dcd9a6"
  vpc        = aws_vpc.gaitg_vpc.id

  tags = {
    Name = "genai.local"
  }
}

resource "aws_service_discovery_service" "genai_tc_be" {
  name = "genai-tc-be"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.genai_local.id
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


