#region ~ locals

locals {
  app = {
    container = {
      name  = "app"
      image = "${var.image_registry}:${var.app_image_tag}"
      port  = 8080
    }
  }
  api = {
    container = {
      name  = "api"
      image = "${var.image_registry}:${var.api_image_tag}"
      port  = 8080
    }
  }
  common_tags = {
    application = var.application
    environment = var.environment
  }
}

#endregion

#region ~ main

resource "aws_service_discovery_http_namespace" "main" {
  name = var.application

  tags = local.common_tags
}

resource "aws_ecs_cluster" "main" {
  name = var.application

  service_connect_defaults {
    namespace = aws_service_discovery_http_namespace.main.arn
  }

  tags = local.common_tags
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 100
  }
}

# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/create-service-connect.html
resource "aws_ecs_service" "app" {
  name                               = "app"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.app.id # https://github.com/hashicorp/terraform/issues/11253
  desired_count                      = 3
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 60
  launch_type                        = "FARGATE"
  scheduling_strategy                = "REPLICA"
  platform_version                   = "LATEST"

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn

    log_configuration {
      log_driver = "awslogs"
      options = {
        awslogs-group         = "/ecs-fargate/${var.application}/service/service-connect-proxy"
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "app"
      }
    }
  }

  network_configuration {
    subnets          = aws_subnet.private.*.id
    assign_public_ip = false
    security_groups  = [aws_security_group.app_service.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = local.app.container.name
    container_port   = local.app.container.port
  }

  deployment_controller {
    type = "ECS"
  }

  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy#preserve-desired-count-when-updating-an-autoscaled-ecs-service
  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  tags = local.common_tags
}

resource "aws_security_group" "app_service" {
  name   = "app-ecs-service"
  vpc_id = aws_vpc.main.id

  # TODO: restrict ingress
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # Only allow traffic in from the load balancer security group
    security_groups = [aws_security_group.lb.id]
  }

  egress {
    protocol         = "-1"
    from_port        = 0
    to_port          = 0
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(local.common_tags, { Name = "app-ecs-service" })
}

resource "aws_security_group" "api_service" {
  name   = "api-ecs-service"
  vpc_id = aws_vpc.main.id

  # TODO: restrict ingress
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # Only allow traffic in from the app service security group
    security_groups = [aws_security_group.app_service.id]
  }

  egress {
    protocol         = "-1"
    from_port        = 0
    to_port          = 0
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(local.common_tags, { Name = "api-ecs-service" })
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.application}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn
  task_role_arn            = aws_iam_role.ecsTaskRole.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  # https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_ContainerDefinition.html
  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/specifying-sensitive-data-secrets.html#secrets-application-retrieval
  container_definitions = jsonencode([
    {
      name      = local.app.container.name
      image     = local.app.container.image
      essential = true
      secrets = [
        {
          name      = "SECRET"
          valueFrom = "${aws_secretsmanager_secret.secret.id}:::"
        },
      ]
      environment = [
        {
          name  = "NAME"
          value = local.app.container.name
        },
        {
          name  = "ENV"
          value = var.environment
        },
        {
          name  = "PORT"
          value = tostring(local.app.container.port)
        },
        {
          name  = "APP_URL"
          value = "https://${aws_lb.main.dns_name}"
        },
        {
          name  = "API_URL"
          value = "http://${local.api.container.name}:${local.api.container.port}"
        },
      ]
      portMappings = [
        {
          name          = local.app.container.name
          containerPort = local.app.container.port
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]
      # healthCheck = {
      #   command = [ "CMD-SHELL", "curl -f http://localhost:8080/ || exit 1" ]
      #   interval = 30
      #   retries  = 3
      #   timeout  = 5
      # }
      privileged             = false
      readonlyRootFilesystem = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs-fargate/${var.application}/service/app"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "app"
        }
      }
      cpu    = 512
      memory = 1024
    }
  ])

  tags = local.common_tags
}

resource "random_id" "secret" {
  keepers = {
    cluster_id = aws_ecs_cluster.main.id
  }

  byte_length = 4
}

resource "aws_secretsmanager_secret" "secret" {
  name = "${local.app.container.name}-secret-${random_id.secret.hex}"

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs-fargate/${var.application}/service/app"
  retention_in_days = var.logs_retention_in_days

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs-fargate/${var.application}/service/api"
  retention_in_days = var.logs_retention_in_days

  tags = local.common_tags
}

# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/create-service-connect.html
resource "aws_ecs_service" "api" {
  name                               = "api"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.api.id # https://github.com/hashicorp/terraform/issues/11253
  desired_count                      = 3
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  launch_type                        = "FARGATE"
  scheduling_strategy                = "REPLICA"
  platform_version                   = "LATEST"

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn

    service {
      client_alias {
        dns_name = local.api.container.name
        port     = local.api.container.port
      }

      port_name = local.api.container.name
    }

    log_configuration {
      log_driver = "awslogs"
      options = {
        awslogs-group         = "/ecs-fargate/${var.application}/service/service-connect-proxy"
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "api"
      }
    }
  }

  network_configuration {
    subnets          = aws_subnet.private.*.id
    assign_public_ip = false
    security_groups  = [aws_security_group.api_service.id]
  }

  deployment_controller {
    type = "ECS"
  }

  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy#preserve-desired-count-when-updating-an-autoscaled-ecs-service
  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.application}-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn
  task_role_arn            = aws_iam_role.ecsTaskRole.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  # https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_ContainerDefinition.html
  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/specifying-sensitive-data-secrets.html#secrets-application-retrieval
  container_definitions = jsonencode([
    {
      name      = local.api.container.name
      image     = local.api.container.image
      essential = true
      secrets   = []
      environment = [
        {
          name  = "NAME"
          value = local.api.container.name
        },
        {
          name  = "ENV"
          value = var.environment
        },
        {
          name  = "PORT"
          value = tostring(local.api.container.port)
        }
      ]
      portMappings = [
        {
          name          = local.api.container.name
          containerPort = local.api.container.port
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]
      privileged             = false
      readonlyRootFilesystem = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs-fargate/${var.application}/service/api"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "api"
        }
      }
      cpu    = 512
      memory = 1024
    }
  ])

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "service_connect_proxy" {
  name              = "/ecs-fargate/${var.application}/service/service-connect-proxy"
  retention_in_days = var.logs_retention_in_days

  tags = local.common_tags
}

#endregion

#region ~ auto scaling

resource "aws_appautoscaling_target" "app" {
  max_capacity       = 10
  min_capacity       = 3
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_target" "api" {
  max_capacity       = 10
  min_capacity       = 3
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-autoscaling-targettracking.html
resource "aws_appautoscaling_policy" "app_ecs_autoscaling_policy_cpu" {
  name               = "${var.application}-app-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.app.resource_id
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension
  service_namespace  = aws_appautoscaling_target.app.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = 60
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }

  depends_on = [aws_appautoscaling_target.app]
}

resource "aws_appautoscaling_policy" "app_esc_autoscaling_policy_memory" {
  name               = "${var.application}-app-memory-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.app.resource_id
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension
  service_namespace  = aws_appautoscaling_target.app.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value       = 80
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }

  depends_on = [aws_appautoscaling_target.app]
}

resource "aws_appautoscaling_policy" "api_ecs_autoscaling_policy_cpu" {
  name               = "${var.application}-api-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension
  service_namespace  = aws_appautoscaling_target.api.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = 60
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }

  depends_on = [aws_appautoscaling_target.api]
}

resource "aws_appautoscaling_policy" "api_esc_autoscaling_policy_memory" {
  name               = "${var.application}-api-memory-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension
  service_namespace  = aws_appautoscaling_target.api.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value       = 80
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }

  depends_on = [aws_appautoscaling_target.api]
}

#endregion

#region ~ network

resource "aws_vpc" "main" {
  cidr_block           = var.vpc
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = "${var.application}" })
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(var.public_subnets, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, { Name = "${var.application}-public" })
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.private_subnets, count.index)
  availability_zone = element(var.availability_zones, count.index)
  count             = length(var.private_subnets)

  tags = merge(local.common_tags, { Name = "${var.application}-private-subnet" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = local.common_tags
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = local.common_tags
}

resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets)
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_nat_gateway" "main" {
  count         = length(var.private_subnets)
  allocation_id = element(aws_eip.nat.*.id, count.index)
  subnet_id     = element(aws_subnet.public.*.id, count.index)

  tags = local.common_tags

  depends_on = [aws_internet_gateway.main]
}

resource "aws_eip" "nat" {
  count = length(var.private_subnets)
  vpc   = true

  tags = local.common_tags
}

resource "aws_route_table" "private" {
  count  = length(var.private_subnets)
  vpc_id = aws_vpc.main.id

  tags = local.common_tags
}

resource "aws_route" "private" {
  count                  = length(compact(var.private_subnets))
  route_table_id         = element(aws_route_table.private.*.id, count.index)
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = element(aws_nat_gateway.main.*.id, count.index)
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets)
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index)
}

resource "aws_lb" "main" {
  name               = var.application
  internal           = false
  load_balancer_type = "application"
  subnets            = aws_subnet.public.*.id
  security_groups    = [aws_security_group.lb.id]

  enable_deletion_protection = false

  tags = local.common_tags
}

resource "aws_security_group" "lb" {
  name   = "${var.application}-lb"
  vpc_id = aws_vpc.main.id

  ingress {
    protocol         = "tcp"
    from_port        = 80
    to_port          = 80
    cidr_blocks      = ["0.0.0.0/0"] # Allowing traffic in from all sources
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    protocol         = "tcp"
    from_port        = 443
    to_port          = 443
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    protocol         = "-1"
    from_port        = 0
    to_port          = 0
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.application}-lb" })
}

resource "aws_lb_target_group" "main" {
  name        = var.application
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    healthy_threshold   = "3"
    interval            = "30"
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = "3"
    path                = "/"
    unhealthy_threshold = "3"
  }

  tags = local.common_tags

  depends_on = [aws_lb.main]
}

resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.main.id
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.main.id

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.id
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "http_redirect_listener" {
  load_balancer_arn = aws_lb.main.id
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = local.common_tags
}

resource "aws_acm_certificate" "main" {
  private_key      = <<EOF
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAy9GHSc00i4E3qNqGZONSQiDKlZV0BNvn26mmwSyyhhL3LAMz
9R2UnLArC+CNCyU1l4NVyM7m6e4PTNBt1LLPRQAZr4jxj3qvVkpfI4Sl8IbLdGE6
VVpvOEzDqfMx6rTZPBKDDjS/sJWRQSJtR4jYbne0dLTgUWXUv746bU+JTrytpODh
be0fjKY892eGQg+SSSObwnBQzt7W6697pp4t7Tkku2xBAkzT9ahKdtCbTs0esGUD
7MbnHxK9J7FMf3Rg+pJE+T5bWBteYW8dD5MaMdVkz2cAwqTL42bBQg0Ad2livIRI
5SZM4lcliBx9PMsl4yCqqnZpz0Y08xLGvNqeNwIDAQABAoIBACrkjXQam1RAfVYr
ptzUehswi3GvYhsjrEeuDEna/jb5BstcYTLUZtISwPxe5U/TJNQd74+y+yV/0/h2
ZKa+eqAqxT0LtMpdJ0khnaP75nAX7fkv/Pa5cW6HuSWq6HZcWNsriikTMMQYtdjf
ReAoDGQzDOcCqbJ3m64+ek1Gz76h1fFDUmQ7hPirQggIucRhNoFJ3/lDiY8phGYT
Td2Ug4zhUamVoni+8UM4Q3x9u58KE+d2FVJWsKaOJE9AUPrnHSo2BgCa7ulzP/1S
8hmxqQmgnMKmzc63XNPC4X9Uxnv4lUXRW0rnNUHUNqgxbWdkZI3gtnIxmdFyTYBn
Cxf2BgECgYEA+AEwj3Bu23o2ZArBhJLQkNMofpi3OpCtK4/MTqOv49wrCIUZBLZJ
F9rjR6tQZIcXyLV0F5/MJ5b3cIB+tzlsxjkR2Dhpwp4CszmjjeGvJ2dXePZ9H5Um
VlNilZUe4wuXyvah1R0BVrNi0gU2xZO7VqZNXzgQsur14fJzMr/u11kCgYEA0mOq
UBFuDtWNDNXgxqN1vuPbnDa5oOJecqSBZR/9tiSQz2NUyy0aHqm9KjScRuCMmC3W
QRTsb/28EB3nvSh6YzH/067+evJ7r5l8RnsJUVG8w2WeI+WHJ4vdKwpdFDNovAjh
PmTnx6+raF3r2aZbBYshnkBazM/k1ewMD408AA8CgYEAuc+6YF3u0QX55m6gmwGc
vkVW27Lz5S8sb6zneCvvxprYqyN9oSgqD3NyQeo663bD/R7mgiS5wxe7AFFln0Wp
F8L+ea+anbPhdgLDZbQnlTA6O2kCSj1nYdpLzKLTZ2zyJ6EtkwyOSjVQ3uYFKXcM
L1meMq9A46xi2Qzb/rQK8NECgYBogzIbzEzL+bGz6ptakeDwDukNVPIpxcn9UVMm
FRpH3SpCm6mHtMQA73kU+kWXv/yXrE1+zxIVIArIRtLT2MPTewcG9StdkA95T9m4
eW5LgzsuJdDFLERTlNstglxyqIciwZaDFEU/oTiZA+8hk84rls4Aex+gFrYqvrPP
Fe30aQKBgF0eV+r7C/F7QiBK17TyivIWX1tAy/wKVnUIQh780xNrg8hsTQuxmDcD
IyhVC2rfstZbTL1W1JayG/+KNCVl6un/0rFsxz7x4NDQ/A5iTsYK6fxIgQ/geVGL
IUbXK15+l6bTuu5avqR7zsvz7s84SpjgCRIZmzfr9v7rRFPe2Xxm
-----END RSA PRIVATE KEY-----
EOF
  certificate_body = <<EOF
-----BEGIN CERTIFICATE-----
MIICrDCCAZQCCQCm6kA3L+ViwDANBgkqhkiG9w0BAQsFADAYMRYwFAYDVQQDDA1m
YWtlLWNlcnQuY29tMB4XDTIzMDExMzExMjU0MVoXDTI0MDExMzExMjU0MVowGDEW
MBQGA1UEAwwNZmFrZS1jZXJ0LmNvbTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC
AQoCggEBAMvRh0nNNIuBN6jahmTjUkIgypWVdATb59uppsEssoYS9ywDM/UdlJyw
KwvgjQslNZeDVcjO5unuD0zQbdSyz0UAGa+I8Y96r1ZKXyOEpfCGy3RhOlVabzhM
w6nzMeq02TwSgw40v7CVkUEibUeI2G53tHS04FFl1L++Om1PiU68raTg4W3tH4ym
PPdnhkIPkkkjm8JwUM7e1uuve6aeLe05JLtsQQJM0/WoSnbQm07NHrBlA+zG5x8S
vSexTH90YPqSRPk+W1gbXmFvHQ+TGjHVZM9nAMKky+NmwUINAHdpYryESOUmTOJX
JYgcfTzLJeMgqqp2ac9GNPMSxrzanjcCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEA
ayP+gq5BYuZd0ZtJEfNRYnMgwZVVM/wAVzLmXjXh4hrCbkYrzj20ZmsGr8HdVZyB
S4QmqNxrcUFdGgdb8fd5NpfsdSAek2iN1d92VoyAi+mJYZ1LlC9/70/PxlRhXyOP
JHI2NFNcxt6nk9bNlyhOLjp+gUtSyDj8l9UTW8u1rEH3DGdteIMB1fF+MFX462b3
aI+XUmlpf+uSMQuMHeVaUqjwMHxvNbmOkvEsOEPQl7p28YCG9j2jjJBRiHvXQoT0
aZakaz7VYQYuCqUwkcg6dvNfj3Z+YgSfkBLtzcoXxkb82oeLwjP58twwgXcVDTZv
7vpZ6om0qwOA+p/QOvbFSw==
-----END CERTIFICATE-----
EOF
}

#endregion

#region ~ iam

data "aws_iam_policy" "permissions_boundary" {
  name = "network-boundary"
}

data "aws_iam_policy_document" "ecs_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = [
        "ecs.amazonaws.com",
        "ecs-tasks.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name                 = "ecsTaskExecutionRole"
  assume_role_policy   = data.aws_iam_policy_document.ecs_assume_role_policy.json
  permissions_boundary = data.aws_iam_policy.permissions_boundary.arn

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy_attachment" {
  role       = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_secret_read_policy" {
  name = "ECSTaskExecutionSecretReadPolicy"
  role = aws_iam_role.ecsTaskExecutionRole.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "kms:Decrypt",
          "secretsmanager:GetSecretValue"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "ecsTaskRole" {
  name                 = "${var.application}-ecsTaskRole"
  assume_role_policy   = data.aws_iam_policy_document.ecs_assume_role_policy.json
  permissions_boundary = data.aws_iam_policy.permissions_boundary.arn

  tags = local.common_tags
}

resource "aws_iam_role_policy" "ecsTaskRole_policy_attachment" {
  name = "${var.application}-ecsTaskRolePolicy"
  role = aws_iam_role.ecsTaskRole.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "dynamodb:CreateTable",
          "dynamodb:UpdateTimeToLive",
          "dynamodb:PutItem",
          "dynamodb:DescribeTable",
          "dynamodb:ListTables",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
          "dynamodb:UpdateTable"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

#endregion