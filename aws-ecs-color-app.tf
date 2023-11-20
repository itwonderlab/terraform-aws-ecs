# Copyright (C) 2018 - 2023 IT Wonder Lab (https://www.itwonderlab.com)
#
# This software may be modified and distributed under the terms
# of the MIT license.  See the LICENSE file for details.
# -------------------------------- WARNING --------------------------------
# IT Wonder Lab's best practices for infrastructure include modularizing 
# Terraform/OpenTofu configuration. 
# In this example, we define everything in a single file. 
# See other tutorials for best practices at itwonderlab.com
# -------------------------------- WARNING --------------------------------

#Define Terrraform Providers and Backend
terraform {
  required_version = "> 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

#-----------------------------------------
# Default provider: AWS
#-----------------------------------------
provider "aws" {
  shared_credentials_files = ["~/.aws/credentials"]
  profile                  = "ditwl_infradmin"
  region                   = "us-east-1" //See BUG https://github.com/hashicorp/terraform-provider-aws/issues/30488
}

# VPC
resource "aws_vpc" "ditlw-vpc" {
  cidr_block = "172.21.0.0/19" #172.21.0.0 - 172.21.31.254
  tags = {
    Name = "ditlw-vpc"
  }
}

# Subnet
resource "aws_subnet" "ditwl-sn-za-pro-pub-00" {
  vpc_id                  = aws_vpc.ditlw-vpc.id
  cidr_block              = "172.21.0.0/23" #172.21.0.0 - 172.21.1.255
  map_public_ip_on_launch = true            #Assign a public IP address
  tags = {
    Name = "ditwl-sn-za-pro-pub-00"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "ditwl-ig" {
  vpc_id = aws_vpc.ditlw-vpc.id
  tags = {
    Name = "ditwl-ig"
  }
}

# Routing table for public subnet (access to Internet)
resource "aws_route_table" "ditwl-rt-pub-main" {
  vpc_id = aws_vpc.ditlw-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ditwl-ig.id
  }

  tags = {
    Name = "ditwl-rt-pub-main"
  }
}

# Set new main_route_table as main
resource "aws_main_route_table_association" "ditwl-rta-default" {
  vpc_id         = aws_vpc.ditlw-vpc.id
  route_table_id = aws_route_table.ditwl-rt-pub-main.id
}

# Create a Security Group
resource "aws_security_group" "ditwl-sg-ecs-color-app" {
  name        = "ditwl-sg-ecs-color-app"
  vpc_id      = aws_vpc.ditlw-vpc.id
}

# Allow access from the Intert to port 8008
resource "aws_security_group_rule" "ditwl-sr-internet-to-ecs-color-app-8080" {
  security_group_id        = aws_security_group.ditwl-sg-ecs-color-app.id
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  cidr_blocks              = ["0.0.0.0/0"] # Internet
}

# Allow all outbound traffic to Internet
resource "aws_security_group_rule" "all_outbund" {
  security_group_id = aws_security_group.ditwl-sg-ecs-color-app.id
  type              = "egress"
  from_port         = "0"
  to_port           = "0"
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# Create an ECS Cluster
resource "aws_ecs_cluster" "ditwl-ecs-01" {
  name = "ditwl-ecs-01"
}

# ECS Task definition (Define infrastructure and container images)
resource "aws_ecs_task_definition" "ditwl-ecs-td-color-app" {
  family                   = "service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256 # Number of cpu units 1024 units = 1 vCPU
  memory                   = 512 # Amount (in MiB)
  container_definitions = jsonencode([
    {
      name      = "ditwl-ecs-td-color-app"
      image     = "itwonderlab/color"
      memory    = 50
      essential = true 
      portMappings = [
        {
          containerPort = 8080
        }
      ]
    }
  ])
}

# ECS Service 
resource "aws_ecs_service" "ditwl-ecs-serv-color-app" {
  name            = "ditwl-ecs-serv-color-app"
  cluster         = aws_ecs_cluster.ditwl-ecs-01.id
  task_definition = aws_ecs_task_definition.ditwl-ecs-td-color-app.arn
  launch_type     = "FARGATE"
  desired_count   = 1
  network_configuration {
    subnets = [aws_subnet.ditwl-sn-za-pro-pub-00.id]
    assign_public_ip = "true"
    security_groups = [aws_security_group.ditwl-sg-ecs-color-app.id]
  }
}

