# Everything an environment needs to exist before anything can be deployed into it: a network, the identity to
# act in it, a cluster, and a way in from outside.
#
# Built once per environment and shared by every slot in it: a slot is a namespace on this cluster, not a
# landing zone of its own. So nothing here is named after a slot — the environment's name is the whole identity.

locals {
  slug    = replace(var.name, "/", "-")
  cluster = substr(local.slug, 0, 38)

  # Sized by stage, not by a size class. What a cluster needs is a property of what it hosts, and a stage
  # already says that — a developer never chooses "large" for an environment they do not own.
  sizing = {
    dev     = { instance_type = "t3.medium", desired = 2, min = 1, max = 4 }
    test    = { instance_type = "t3.medium", desired = 2, min = 1, max = 4 }
    staging = { instance_type = "m6i.large", desired = 3, min = 2, max = 8 }
    prod    = { instance_type = "m6i.xlarge", desired = 6, min = 3, max = 24 }
  }
  size = local.sizing[var.stage]

  # Production keeps its control-plane logs; below it they are noise nobody reads and storage somebody pays
  # for.
  log_types = var.stage == "prod" ? ["api", "audit", "authenticator"] : []

  # One NAT per zone in production so a zone failure does not take the others' egress with it; one shared
  # below it, because three idle NAT gateways is a bill without a reader.
  nat_count = var.stage == "prod" ? var.availability_zones : 1

  zones = [for index in range(var.availability_zones) : "${var.region}${substr("abcd", index, 1)}"]

  secret_ref = "${var.name}/kubeconfig"
  domain     = var.ingress_domain != "" ? var.ingress_domain : "${local.slug}.internal"

  # The two workloads that need to act on this account from inside the cluster, by the service account each
  # is bound to. Named here rather than inline so the roles and the policy documents cannot drift apart.
  irsa_service_accounts = {
    "aws-load-balancer-controller" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
    "external-dns"                 = "system:serviceaccount:kube-system:external-dns"
  }

  tags = merge(var.tags, {
    "lembos.dev/environment" = var.name
    "lembos.dev/stage"       = var.stage
  })
}

# ── Network ──

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.tags, { Name = local.cluster })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = local.cluster })
}

# Public subnets carry the load balancer and the NAT gateways; nothing else belongs in them. The tag is
# what lets the AWS load balancer controller discover them without being told.
resource "aws_subnet" "public" {
  count = var.availability_zones

  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(aws_vpc.this.cidr_block, 4, count.index)
  availability_zone       = local.zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name                                     = "${local.cluster}-public-${count.index}"
    "kubernetes.io/role/elb"                 = "1"
    "kubernetes.io/cluster/${local.cluster}" = "shared"
  })
}

# Private subnets carry the nodes and everything they run. Offset past the public block so the two never
# overlap however many zones are asked for.
resource "aws_subnet" "private" {
  count = var.availability_zones

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(aws_vpc.this.cidr_block, 4, count.index + 8)
  availability_zone = local.zones[count.index]

  tags = merge(local.tags, {
    Name                                     = "${local.cluster}-private-${count.index}"
    "kubernetes.io/role/internal-elb"        = "1"
    "kubernetes.io/cluster/${local.cluster}" = "shared"
  })
}

resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${local.cluster}-nat-${count.index}" })
}

resource "aws_nat_gateway" "this" {
  count = local.nat_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = merge(local.tags, { Name = "${local.cluster}-${count.index}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.tags, { Name = "${local.cluster}-public" })
}

resource "aws_route_table_association" "public" {
  count = var.availability_zones

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One table per private subnet, because each may egress through a different NAT. Below production they all
# resolve to the same one, which is the arrangement nat_count describes.
resource "aws_route_table" "private" {
  count = var.availability_zones

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index % local.nat_count].id
  }

  tags = merge(local.tags, { Name = "${local.cluster}-private-${count.index}" })
}

resource "aws_route_table_association" "private" {
  count = var.availability_zones

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ── Security groups ──

# The only thing reachable from the internet. Everything else is reachable from this or from the cluster.
resource "aws_security_group" "alb" {
  name        = "${local.cluster}-alb"
  description = "Ingress from the internet to the load balancer."
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from anywhere."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP, which the listener redirects."
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.cluster}-alb" })
}

resource "aws_security_group" "node" {
  name        = "${local.cluster}-node"
  description = "The cluster's nodes."
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Traffic between nodes."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description     = "Traffic the load balancer forwards."
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.cluster}-node" })
}

# ── Identity ──

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.cluster}-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${local.cluster}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = local.tags
}

# ── Cluster ──

resource "aws_eks_cluster" "this" {
  name     = local.cluster
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  enabled_cluster_log_types = local.log_types

  vpc_config {
    # Nodes live in the private subnets; the public ones exist for the load balancer. Both are given to
    # the cluster so the controller can place internal and internet-facing load balancers itself.
    subnet_ids         = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
    security_group_ids = [aws_security_group.node.id]

    # Reachable from outside only below production; production is entered through the platform's own path.
    endpoint_public_access  = var.stage != "prod"
    endpoint_private_access = true
  }

  tags = local.tags
}

# What makes a pod able to assume a role without a static credential. Created here rather than left to a
# later step, because every IRSA role in this environment trusts it and there is nothing to trust until it
# exists.
#
# Gated on the input rather than on the issuer itself. The issuer is an attribute of the cluster, so on a
# first plan it is unknown — and a count cannot be derived from an unknown — while on the plan after an
# emulated apply it is a known empty list, and `identity[0]` then fails the entire plan on an index. Only
# something answerable before the cluster exists can decide this, which is why it is a variable.
data "tls_certificate" "oidc" {
  count = var.irsa_enabled ? 1 : 0

  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  count = var.irsa_enabled ? 1 : 0

  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc[0].certificates[0].sha1_fingerprint]
  tags            = local.tags
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.cluster}-workers"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = [local.size.instance_type]

  scaling_config {
    desired_size = local.size.desired
    min_size     = local.size.min
    max_size     = local.size.max
  }

  tags = local.tags
}

# The two workloads that need to act on this account from inside the cluster. Scoped to their own service
# accounts by the subject condition, so a pod in another namespace cannot assume them.
data "aws_iam_policy_document" "irsa_assume" {
  # None of them without the provider to trust: a role whose federated principal does not exist is a role
  # nothing can assume, and creating it would leave the cluster looking equipped when it is not.
  for_each = var.irsa_enabled ? local.irsa_service_accounts : {}

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.this[0].url, "https://", "")}:sub"
      values   = [each.value]
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each = data.aws_iam_policy_document.irsa_assume

  name               = "${local.cluster}-${each.key}"
  assume_role_policy = each.value.json
  tags               = local.tags
}

# ── Ingress ──

resource "aws_lb" "this" {
  name               = substr("${local.cluster}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = local.tags
}

# Empty until something registers itself. The controller in the cluster fills it from an Ingress; what this
# module owns is the load balancer being there and reachable at a known name.
resource "aws_lb_target_group" "default" {
  name        = substr("${local.cluster}-default", 0, 32)
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    path    = "/healthz"
    matcher = "200-399"
  }

  tags = local.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }
}

# Private, because these names resolve inside the VPC. A public zone is a delegation somebody has to
# accept, which is a decision an environment blueprint should not be making on its own.
resource "aws_route53_zone" "this" {
  name = local.domain

  vpc {
    vpc_id = aws_vpc.this.id
  }

  tags = local.tags
}

# One record for everything the environment publishes. A component's ingress host is built from this, so a
# new component needs no DNS change of its own.
resource "aws_route53_record" "wildcard" {
  zone_id = aws_route53_zone.this.zone_id
  name    = "*.${local.domain}"
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

# ── How something reaches the cluster ──

# The path is what leaves this module; the certificate and the token do not.
resource "aws_secretsmanager_secret" "kubeconfig" {
  name = local.secret_ref
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "kubeconfig" {
  secret_id = aws_secretsmanager_secret.kubeconfig.id

  secret_string = jsonencode({
    url                   = aws_eks_cluster.this.endpoint
    cluster               = aws_eks_cluster.this.name
    certificate_authority = try(aws_eks_cluster.this.certificate_authority[0].data, null)
  })
}
