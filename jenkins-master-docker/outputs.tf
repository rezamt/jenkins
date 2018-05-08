output "jenkins-master-ecr-repo-url" {
  value = "${aws_ecr_repository.jenkins-master.repository_url}"
}

output "jenkins-master-ecr-id" {
  value = "${aws_ecr_repository.jenkins-master.registry_id}"
}
