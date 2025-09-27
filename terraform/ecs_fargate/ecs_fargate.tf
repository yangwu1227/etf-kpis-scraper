# ECS Cluster
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${var.stack_name}_ecs_cluster"

  # Enable container insights for the ECS cluster
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.tags
}

# ECS Cluster Capacity Providers
resource "aws_ecs_cluster_capacity_providers" "ecs_cluster_capacity_providers" {
  cluster_name       = aws_ecs_cluster.ecs_cluster.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  # Split evenly between FARGATE and FARGATE_SPOT
  default_capacity_provider_strategy {
    weight            = 1
    capacity_provider = "FARGATE"
  }

  default_capacity_provider_strategy {
    weight            = 1
    capacity_provider = "FARGATE_SPOT"
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "ecs_task_definition" {
  family                   = "${var.stack_name}_task_definition"
  execution_role_arn       = data.terraform_remote_state.iam.outputs.ecs_execution_role_arn
  task_role_arn            = data.terraform_remote_state.iam.outputs.ecs_task_role_arn
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  requires_compatibilities = ["FARGATE"]

  # Runtime platform
  runtime_platform {
    cpu_architecture        = var.cpu_architecture
    operating_system_family = var.operating_system_family
  }

  # Ephemeral storage
  ephemeral_storage {
    size_in_gib = var.size_in_gib
  }

  # Container definitions
  container_definitions = jsonencode([
    {
      name      = "${var.stack_name}_container"
      image     = "${local.aws_account_id}.dkr.ecr.${local.aws_region}.amazonaws.com/${data.terraform_remote_state.s3_ecr.outputs.ecr_repo_name}:latest"
      essential = true
      environmentFiles = [
        {
          type  = "s3"
          value = var.environment_file_s3_arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-create-group  = "true"
          awslogs-group         = "/aws/ecs/${var.stack_name}"
          awslogs-region        = local.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = local.tags
}
