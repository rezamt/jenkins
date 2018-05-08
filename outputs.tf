output "JenkinsELB" {
  value = "Use the following URL to access Jenkins: http://${aws_elb.JenkinsELB.dns_name}/"
}