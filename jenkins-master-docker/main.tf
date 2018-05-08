resource "aws_ecr_repository" "jenkins-master" {
  name = "jenkins-master"
}

resource "null_resource" "jenkins-master-docker-build" {
  provisioner "local-exec" {
    command = "docker build -t ${var.jenkins-master-node} ."
  }

  provisioner "local-exec" {
    command = "docker tag ${var.jenkins-master-node}:latest ${aws_ecr_repository.jenkins-master.repository_url}:latest"
  }

  depends_on = [
    "aws_ecr_repository.jenkins-master"]
}

resource "null_resource" "jenkins-master-ecr-access" {
  provisioner "local-exec" {
    command = "aws ecr get-login --no-include-email"
  }

  depends_on = [
    "null_resource.jenkins-master-docker-build"]
}


resource "null_resource" "jenkins-master-ecr-submit" {

  provisioner "local-exec" {
    command = "aws ecr get-login --no-include-email > /tmp/ecr-login.sh"
  }

  provisioner "local-exec" {
    command = "/tmp/ecr-login.sh"
  }

  provisioner "local-exec" {
    command = "docker push ${aws_ecr_repository.jenkins-master.repository_url}:latest"
  }

  depends_on = [
    "null_resource.jenkins-master-ecr-access"]
}

resource "null_resource" "jenkins-master-cleanup" {

  provisioner "local-exec" {
    command = "rm -f /tmp/ecr_login.sh"
  }

  provisioner "local-exec" {
    command = "docker login -u AWS"
  }

  depends_on = ["null_resource.jenkins-master-ecr-submit"]
}