#region ~ locals

locals {
  common_tags = {
    application = var.application
    environment = var.environment
  }
}

#endregion

#region iam

data "aws_iam_policy" "permissions_boundary" {
  name = "network-boundary"
}

resource "aws_iam_user" "user" {
  name = "${var.application}-publisher"
  path = "/"
  permissions_boundary = data.aws_iam_policy.permissions_boundary.arn

  tags = local.common_tags
}

resource "aws_iam_user_policy_attachment" "user_policy_attachment" {
  user       = aws_iam_user.user.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_access_key" "access_key" {
  user = aws_iam_user.user.name
}

#endregion

#region s3

resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.application}-tfstate"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  policy = data.aws_iam_policy_document.terraform_state.json
}

data "aws_iam_policy_document" "terraform_state" {
  statement {
    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.user.arn]
    }

    actions = [
      "s3:*",
    ]

    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*",
    ]
  }
}

#endregion

#region ecr

resource "aws_ecr_repository" "repository" {
  name                 = "${var.application}-registry"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

#endregion
