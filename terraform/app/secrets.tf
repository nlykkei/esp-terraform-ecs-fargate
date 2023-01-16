data "aws_secretsmanager_secret_version" "lb_tls_cert" {
  secret_id = "arn:aws:secretsmanager:eu-central-1:902566026396:secret:esp-lb-tls-cert-LYm7CA"
}

data "aws_secretsmanager_secret_version" "lb_tls_key" {
  secret_id = "arn:aws:secretsmanager:eu-central-1:902566026396:secret:esp-lb-tls-key-vW73PB"
}

data "aws_secretsmanager_secret" "app_secret" {
  arn = "arn:aws:secretsmanager:eu-central-1:902566026396:secret:esp-app-secret-Db5mAb"
}
