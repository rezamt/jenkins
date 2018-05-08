# Configure the AWS Provider
provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region = "${var.region}"
}


resource "aws_vpc" "main" {
  cidr_block = "${var.vpc_cidr}"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags {
    Name = "Main"
    Key = "Application"
    Group = "Jenkins CD/CI"
  }
}

resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.main.id}"
  tags {
    Name = "Jenkins"
    Network = "Public"
  }
}

resource "aws_subnet" "dmz" {
  cidr_block = "${var.vpc_cidr}"
  vpc_id = "${aws_vpc.main.id}"
  tags {
    Name = "dmz"
  }
}


resource "aws_route_table" "internet" {
  vpc_id = "${aws_vpc.main.id}"

  route {
    cidr_block = "${var.internet_cidr}"
    gateway_id = "${aws_internet_gateway.default.id}"
  }

  tags {
    Name = "main"
  }
}

resource "aws_route_table_association" "dmz" {
  subnet_id = "${aws_subnet.dmz.id}"
  route_table_id = "${aws_route_table.internet.id}"
}

resource "aws_iam_role_policy" "ECSServiceRolePolicy" {
  name = "ECSServicePolicy"
  policy = "${data.aws_iam_policy_document.ecs-service-role-policy-doc.json}"
  role = "${aws_iam_role.ECSServiceRole.name}"
}

resource "aws_iam_role" "ECSServiceRole" {
  name = "ECSServiceRole"
  path = "/"
  assume_role_policy = "${data.aws_iam_policy_document.ecs-service-assume-role-policy-doc.json}"
}


resource "aws_iam_role_policy" "EC2RolePolicy" {
  name = "EC2RolePolicy"
  policy = "${data.aws_iam_policy_document.ec2-role-policy-doc.json}"
  role = "${aws_iam_role.EC2Role.name}"
}

resource "aws_iam_role" "EC2Role" {
  name = "EC2Role"
  path ="/"
  assume_role_policy = "${data.aws_iam_policy_document.ec2-assume-role-policy-doc.json}"
}

resource "aws_iam_instance_profile" "JenkinsECSInstanceProfile" {
  path = "/"
  name = "JenkinsECSInstanceProfile"
  role = "${aws_iam_role.EC2Role.name}"
}

resource "aws_security_group" "JenkinsSecurityGroup" {
  name = "JenkinsSecurityGroup"
  description = "SecurityGroup for Jenkins instances: master and slaves"
  vpc_id = "${aws_vpc.main.id}"
  tags {
    Name = "JenkinsSecurityGroup"
  }

  ingress {
    from_port = 22
    protocol = "tcp"
    to_port = 22
    cidr_blocks = ["${var.internet_cidr}"]
  }

  ingress {
    from_port = 8080
    protocol = "tcp"
    to_port = 8080
    cidr_blocks = ["${var.vpc_cidr}"]
  }

  ingress {
    from_port = 50000
    protocol = "tcp"
    to_port = 50000
    cidr_blocks = ["${var.vpc_cidr}"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "JenkinsELBSecurityGroup" {
  name = "JenkinsELBSecurityGroup"
  description = "SecurityGroup for Jenkins ELB"
  vpc_id = "${aws_vpc.main.id}"

  ingress {
    from_port = 80
    protocol = "tcp"
    to_port = 80
    cidr_blocks = ["${var.internet_cidr}"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "JenkinsELBSecurityGroup"
  }
}


resource "aws_security_group" "EFSSecurityGroup" {
  name = "EFSSecurityGroup"
  description = "Security group for EFS mount target"
  vpc_id = "${aws_vpc.main.id}"

  ingress {
    from_port = 2049
    protocol = "tcp"
    to_port = 2049
    cidr_blocks = ["${var.vpc_cidr}"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "EFSSecurityGroup"
  }
}

resource "aws_efs_file_system" "JenkinsEFS" {
  creation_token = "JenkinsEFS"

  tags {
    Name = "JenkinsEFS"
  }
}

resource "aws_efs_mount_target" "MountTarget" {
  file_system_id = "${aws_efs_file_system.JenkinsEFS.id}"
  subnet_id = "${aws_subnet.dmz.id}"
  security_groups = ["${aws_security_group.EFSSecurityGroup.id}"]
}


resource "aws_elb" "JenkinsELB" {
  name = "jenkins-elb"

  "listener" {
    instance_port = 8080
    instance_protocol = "http"
    lb_port = 80
    lb_protocol = "http"
  }

  health_check {
    healthy_threshold = 3
    interval = 20
    target = "HTTP:8080/login"
    timeout = 2
    unhealthy_threshold = 10
  }

  subnets = ["${aws_subnet.dmz.id}"]
  internal = false

  security_groups = ["${aws_security_group.JenkinsELBSecurityGroup.id}"]

  tags {
    Name = "jenkins-elb"
  }
}

resource "aws_lb_cookie_stickiness_policy" "JenkinsELBStickiness" {
  name                     = "JenkinsELBStickiness"
  load_balancer            = "${aws_elb.JenkinsELB.id}"
  lb_port                  = 80
  cookie_expiration_period = 3600
}

resource "aws_ecs_cluster" "JenkinsCluster" {
  name = "jenkins-cluster"
}

resource "aws_ecs_task_definition" "JenkinsMasterTaskDefinition" {
  container_definitions = "${file("task-definitions/master-service.json")}"
  family = "jenkins-master"
  network_mode = "bridge"
  volume {
    name = "data-volume"
    host_path = "/data"
  }
}

resource "aws_ecs_service" "JenkinsECSService" {
  name            = "JenkinsECSService"
  cluster         = "${aws_ecs_cluster.JenkinsCluster.arn}"
  task_definition = "${aws_ecs_task_definition.JenkinsMasterTaskDefinition.arn}"
  desired_count   = 1
  iam_role        = "${aws_iam_role.ECSServiceRole.arn}"
  depends_on      = ["aws_elb.JenkinsELB"]

  load_balancer {
    elb_name       = "${aws_elb.JenkinsELB.name}"
    container_name = "jenkins-master"
    container_port = 8080
  }
}

data "template_file" "autoscale_init" {
  template = "${file("user-data/autoscale_init.tpl")}"

  vars {
    aws_region = "${var.region}"
    jenkins_cluster = "${aws_ecs_cluster.JenkinsCluster.name}"
    jenkins_efs = "${aws_efs_file_system.JenkinsEFS.id}"
  }
}

resource "aws_key_pair" "jenkins" {
  key_name   = "jenkins"
  public_key = "YOUR-SSH-KEY"
}

resource "aws_launch_configuration" "JenkinsECSLaunchConfiguration" {
  name = "JenkinsECSLaunchConfiguration"
  associate_public_ip_address = true
  image_id = "${var.image_id}"
  iam_instance_profile = "${aws_iam_instance_profile.JenkinsECSInstanceProfile.id}"
  instance_type = "${var.instance_id}"
  security_groups = ["${aws_security_group.JenkinsSecurityGroup.id}"]
  ebs_block_device {
    device_name = "/dev/xvdcz"
    volume_size = 24
    delete_on_termination = true
  }

  key_name = "${aws_key_pair.jenkins.key_name}"
  user_data = "${data.template_file.autoscale_init.rendered}"
/*
  user_data = <<-EOF
    #!/usr/bin/env bash

    echo ECS_CLUSTER=jenkins-cluster >> /etc/ecs/ecs.config

    # Mount EFS volume
    yum install -y nfs-utils

    EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`

    EC2_REGION="${var.region}"

    EFS_FILE_SYSTEM_ID="${aws_efs_file_system.JenkinsEFS.id}"

    EFS_PATH=$EC2_AVAIL_ZONE.$EFS_FILE_SYSTEM_ID.efs.$EC2_REGION.amazonaws.com

    mkdir /data
    mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 $EFS_PATH:/ /data

    # Give ownership to jenkins user
    chown 1000 /data
  EOF
*/
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "JenkinsECSAutoScaling" {
  launch_configuration = "${aws_launch_configuration.JenkinsECSLaunchConfiguration.name}"
  vpc_zone_identifier = ["${aws_subnet.dmz.id}"]
  min_size = 2
  max_size = 5
  desired_capacity = 2
  health_check_type = "EC2"
  health_check_grace_period = "400"
  depends_on = ["aws_efs_mount_target.MountTarget"]
  tags = [
    {
      key                 = "Name"
      value               = "jenkins-ecs-instance"
      propagate_at_launch = true
    }
  ]
}

resource "aws_autoscaling_policy" "JenkinsClusterScaleUpPolicy" {
  name = "JenkinsClusterScaleUpPolicy"
  adjustment_type = "ChangeInCapacity"
  autoscaling_group_name = "${aws_autoscaling_group.JenkinsECSAutoScaling.id}"
  estimated_instance_warmup = 60
  metric_aggregation_type = "Average"
  policy_type = "StepScaling"
  step_adjustment {
    metric_interval_lower_bound = 0
    scaling_adjustment = 2
  }
}

resource "aws_cloudwatch_metric_alarm" "JenkinsClusterScaleUpAlarm" {
  alarm_description = "CPU utilization peaked at 70% during the last minute"
  alarm_name = "JenkinsClusterScaleUpAlarm"
  alarm_actions = ["${aws_autoscaling_policy.JenkinsClusterScaleUpPolicy.arn}"]
  dimensions = [{
    Name = "ClusterName"
    Value = "jenkins-cluster"
  }]
  metric_name = "CPUReservation"
  namespace = "AWS/ECS"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  statistic = "Maximum"
  threshold = 70
  period = 60
  evaluation_periods = 1
  treat_missing_data = "notBreaching"
}

resource "aws_autoscaling_policy" "JenkinsClusterScaleDownPolicy" {
  name = "JenkinsClusterScaleDownPolicy"
  adjustment_type = "PercentChangeInCapacity"
  autoscaling_group_name = "${aws_autoscaling_group.JenkinsECSAutoScaling.id}"
  cooldown = 120
  scaling_adjustment = -50
}

resource "aws_cloudwatch_metric_alarm" "JenkinsClusterScaleDownAlarm" {
  alarm_description = "CPU utilization is under 50% for the last 10 min (change 10 min to 45 min for prod use as you pay by the hour )"
  alarm_name = "JenkinsClusterScaleDownAlarm"
  alarm_actions = ["${aws_autoscaling_policy.JenkinsClusterScaleDownPolicy.arn}"]
  dimensions = [{
    Name = "ClusterName"
    Value = "jenkins-cluster"
  }]
  metric_name = "CPUReservation"
  namespace = "AWS/ECS"
  comparison_operator = "LessThanThreshold"
  statistic = "Maximum"
  threshold = 50
  period = 600
  evaluation_periods = 1
  treat_missing_data = "notBreaching"
}