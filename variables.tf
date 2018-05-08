variable "aws_access_key" {}

variable "aws_secret_key" {}

variable "region" {
  default = "ap-southeast-2"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "internet_cidr" {
  default = "0.0.0.0/0"
}

variable "master_service_docker" {
  default = "ticketfly/jenkins-example-aws-ecs"
}

variable "task_service_docker" {
  default = "ticketfly/jenkins-example-aws-ecs"
}

variable "instance_id" {
  default = "t2.small"
}

variable "image_id" {
  default = "ami-c3233ba0"
}