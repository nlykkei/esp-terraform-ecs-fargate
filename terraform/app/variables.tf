variable "application" {
  type = string
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc" {
  type = string
}

variable "public_subnets" {
  type = list(string)
}

variable "private_subnets" {
  type = list(string)
}

variable "availability_zones" {
  type = list(string)
}

variable "image_registry" {
  type = string
}

variable "app_image_tag" {
  type    = string
  default = "latest"
}

variable "api_image_tag" {
  type    = string
  default = "latest"
}

variable "logs_retention_in_days" {
  type    = number
  default = 90
}

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "aws_profile" {
  type    = string
  default = null
}


