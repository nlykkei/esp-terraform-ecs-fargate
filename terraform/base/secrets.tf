resource "aws_secretsmanager_secret" "lb_tls_cert" {
  name = "${var.application}-lb-tls-cert"
  recovery_window_in_days = 30

  tags = local.common_tags
}

resource "aws_secretsmanager_secret" "lb_tls_key" {
  name = "${var.application}-lb-tls-key"
  recovery_window_in_days = 30

  tags = local.common_tags
}

resource "aws_secretsmanager_secret" "app_secret" {
  name = "${var.application}-app-secret"
  recovery_window_in_days = 30

  tags = local.common_tags
}