data "aws_iam_policy_document" "ecs-service-role-policy-doc" {
  statement {
    actions = [
      "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:Describe*",
      "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
      "elasticloadbalancing:RegisterTargets",
      "ec2:Describe*",
      "ec2:AuthorizeSecurityGroupIngress"
    ]
    resources = ["*"]
    effect = "Allow"
  }

}

data "aws_iam_policy_document" "ecs-service-assume-role-policy-doc" {

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = [
        "ecs.amazonaws.com"]
    }
    effect = "Allow"
  }
}

data "aws_iam_policy_document" "ec2-role-policy-doc" {
  statement {
    actions = [
      "ecs:*",
      "elasticloadbalancing:Describe*",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
    effect = "Allow"
  }
}


data "aws_iam_policy_document" "ec2-assume-role-policy-doc" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = [
        "ec2.amazonaws.com"]
    }
    effect = "Allow"
  }
}
