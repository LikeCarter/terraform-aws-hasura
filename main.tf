# -----------------------------------------------------------------------------
# Create VPC
# -----------------------------------------------------------------------------

# Fetch AZs in the current region
data "aws_availability_zones" "available" {
}

resource "aws_vpc" "okatee" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = var.vpc_enable_dns_hostnames

  tags = {
    Name = "okatee"
  }
}

# Create var.az_count private subnets for RDS, each in a different AZ
resource "aws_subnet" "okatee_private" {
  count             = var.az_count
  cidr_block        = cidrsubnet(aws_vpc.okatee.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  vpc_id            = aws_vpc.okatee.id

  tags = {
    Name = "okatee #${count.index} (private)"
  }
}

# Create var.az_count public subnets for okatee, each in a different AZ
resource "aws_subnet" "okatee_public" {
  count                   = var.az_count
  cidr_block              = cidrsubnet(aws_vpc.okatee.cidr_block, 8, var.az_count + count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  vpc_id                  = aws_vpc.okatee.id
  map_public_ip_on_launch = true

  tags = {
    Name = "okatee #${var.az_count + count.index} (public)"
  }
}

# IGW for the public subnet
resource "aws_internet_gateway" "okatee" {
  vpc_id = aws_vpc.okatee.id

  tags = {
    Name = "okatee"
  }
}

# Route the public subnet traffic through the IGW
resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.okatee.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.okatee.id
}

# -----------------------------------------------------------------------------
# Create security groups
# -----------------------------------------------------------------------------

# Internet to ALB
resource "aws_security_group" "okatee_alb" {
  name        = "okatee-alb"
  description = "Allow access on port 443 only to ALB"
  vpc_id      = aws_vpc.okatee.id

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ALB TO ECS
resource "aws_security_group" "okatee_ecs" {
  name        = "okatee-tasks"
  description = "allow inbound access from the ALB only"
  vpc_id      = aws_vpc.okatee.id

  ingress {
    protocol        = "tcp"
    from_port       = var.container_port
    to_port         = var.host_port
    security_groups = [aws_security_group.okatee_alb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------------------------------------------------------
# Create ECS cluster
# -----------------------------------------------------------------------------

resource "aws_ecs_cluster" "okatee" {
  name = "${var.ecs_cluster_name}"
}

# -----------------------------------------------------------------------------
# Create logging
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "okatee" {
  name = "/ecs/okatee"
}

# -----------------------------------------------------------------------------
# Create IAM for logging
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "okatee_log_publishing" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:PutLogEventsBatch",
    ]

    resources = ["arn:aws:logs:${var.region}:*:log-group:/ecs/okatee:*"]
  }
}

resource "aws_iam_policy" "okatee_log_publishing" {
  name        = "okatee-log-pub"
  path        = "/"
  description = "Allow publishing to cloudwach"

  policy = data.aws_iam_policy_document.okatee_log_publishing.json
}

data "aws_iam_policy_document" "okatee_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "okatee_role" {
  name               = "okatee-role"
  path               = "/system/"
  assume_role_policy = data.aws_iam_policy_document.okatee_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "okatee_role_log_publishing" {
  role       = aws_iam_role.okatee_role.name
  policy_arn = aws_iam_policy.okatee_log_publishing.arn
}

# -----------------------------------------------------------------------------
# Create a task definition
# -----------------------------------------------------------------------------

locals {
  ecs_environment = [
    {
      name  = "foo",
      value = "bar"
    }
  ]

  ecs_container_definitions = [
    {
      image       = "${var.docker_image}"
      name        = "okatee",
      networkMode = "awsvpc",

      portMappings = [
        {
          containerPort = var.container_port,
          hostPort      = var.host_port,
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = "${aws_cloudwatch_log_group.okatee.name}",
          awslogs-region        = "${var.region}",
          awslogs-stream-prefix = "ecs"
        }
      }

      environment = local.ecs_environment
    }
  ]
}

resource "aws_ecs_task_definition" "okatee" {
  family                   = "okatee"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.container_cpu
  memory                   = var.container_memory
  execution_role_arn       = aws_iam_role.okatee_role.arn

  container_definitions = jsonencode(local.ecs_container_definitions)
}

# -----------------------------------------------------------------------------
# Create the ECS service
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "okatee" {
  depends_on = [
    aws_ecs_task_definition.okatee,
    aws_cloudwatch_log_group.okatee,
    aws_alb_listener.okatee
  ]
  name            = "okatee-service"
  cluster         = aws_ecs_cluster.okatee.id
  task_definition = aws_ecs_task_definition.okatee.arn
  desired_count   = var.multi_az == true ? "2" : "1"
  launch_type     = "FARGATE"

  network_configuration {
    assign_public_ip = true
    security_groups  = [aws_security_group.okatee_ecs.id]
    subnets          = aws_subnet.okatee_public.*.id
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.okatee.id
    container_name   = "okatee"
    container_port   = var.container_port
  }
}

# -----------------------------------------------------------------------------
# Create the ALB log bucket
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "okatee" {
  bucket        = "okatee-${var.region}-${var.okatee_subdomain}-${var.domain}"
  acl           = "private"
  force_destroy = "true"
}

# -----------------------------------------------------------------------------
# Add IAM policy to allow the ALB to log to it
# -----------------------------------------------------------------------------

data "aws_elb_service_account" "main" {
}

data "aws_iam_policy_document" "okatee" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.okatee.arn}/alb/*"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "okatee" {
  bucket = aws_s3_bucket.okatee.id
  policy = data.aws_iam_policy_document.okatee.json
}

# -----------------------------------------------------------------------------
# Create the ALB
# -----------------------------------------------------------------------------

resource "aws_alb" "okatee" {
  name            = "okatee-alb"
  subnets         = aws_subnet.okatee_public.*.id
  security_groups = [aws_security_group.okatee_alb.id]

  access_logs {
    bucket  = aws_s3_bucket.okatee.id
    prefix  = "alb"
    enabled = true
  }
}

# -----------------------------------------------------------------------------
# Create the ALB target group for ECS
# -----------------------------------------------------------------------------

resource "aws_alb_target_group" "okatee" {
  name        = "okatee-alb"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.okatee.id
  target_type = "ip"

  health_check {
    path    = "/healthz"
    matcher = "200"
  }
}

# -----------------------------------------------------------------------------
# Create the ALB listener
# -----------------------------------------------------------------------------

resource "aws_alb_listener" "okatee" {
  load_balancer_arn = aws_alb.okatee.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.okatee.id
    type             = "forward"
  }
}
