# A managed Postgres cluster with backups, PITR, and a read replica.

locals {
  slug = replace(var.name, "/", "-")

  # One per placement. The same resource stands in every slot it is placed in, and an instance identifier is unique
  # per account and region — two slots of one environment share both. Cut to leave room under the 63 characters RDS
  # allows for a replica's "-replica-N", with a hash of the whole so two long names still differ.
  placement  = lower(join("-", [replace(var.environment, "/", "-"), var.stamp, local.slug]))
  identifier = length(local.placement) <= 50 ? local.placement : "${trimsuffix(substr(local.placement, 0, 41), "-")}-${substr(md5(local.placement), 0, 8)}"

  # What a size class means for Postgres. The platform team owns this table; the developer who
  # declared `postgres` at `small` does not have to know what an instance class is.
  sizing = {
    small  = { instance_class = "db.t4g.small", storage = 20, multi_az = false, replicas = 0 }
    medium = { instance_class = "db.t4g.large", storage = 100, multi_az = true, replicas = 1 }
    large  = { instance_class = "db.r6g.xlarge", storage = 500, multi_az = true, replicas = 2 }
  }
  size = local.sizing[var.size_class]

  # Production keeps a month; anything below it keeps a week. Retention is a stage decision, not a
  # size decision, which is why it is not in the table above.
  backup_retention = can(regex("prod", var.environment)) ? 30 : 7

  secret_ref = "${var.environment}/${var.stamp}/${var.name}"

  tags = merge(var.tags, {
    "lembos.dev/resource"    = var.name
    "lembos.dev/environment" = var.environment
    "lembos.dev/stamp"       = var.stamp
  })
}

resource "random_password" "master" {
  length  = 32
  special = false
}

resource "aws_db_instance" "this" {
  identifier     = local.identifier
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = local.size.instance_class

  allocated_storage = local.size.storage
  storage_encrypted = true
  multi_az          = local.size.multi_az

  db_name  = replace(local.slug, "-", "_")
  username = "lembos"
  password = random_password.master.result

  backup_retention_period = local.backup_retention
  skip_final_snapshot     = local.backup_retention < 30
  deletion_protection     = local.backup_retention >= 30
  apply_immediately       = true

  tags = local.tags
}

resource "aws_db_instance" "replica" {
  count = local.size.replicas

  identifier          = "${local.identifier}-replica-${count.index}"
  replicate_source_db = aws_db_instance.this.identifier
  instance_class      = local.size.instance_class
  skip_final_snapshot = true

  tags = local.tags
}

# The credential lands in the secret store and its path is what leaves this module. Terraform state
# holds the password because it created it; nothing downstream needs to.
resource "aws_secretsmanager_secret" "connection" {
  name = local.secret_ref
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "connection" {
  secret_id = aws_secretsmanager_secret.connection.id
  secret_string = jsonencode({
    url = format("postgresql://%s:%s@%s:%d/%s",
      aws_db_instance.this.username,
      random_password.master.result,
      aws_db_instance.this.address,
      aws_db_instance.this.port,
    aws_db_instance.this.db_name)
  })
}
