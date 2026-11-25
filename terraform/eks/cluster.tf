# EKS 컨트롤 플레인: 쿠버네티스 API 서버를 AWS가 대신 운영한다 (시간당 $0.10).
resource "aws_iam_role" "cluster" {
  name = "${local.cluster}-cluster"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "main" {
  name     = local.cluster
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  # 접근 권한은 aws-auth ConfigMap 대신 Access Entry(EKS API)로 관리한다.
  # 클러스터를 만든 사용자(terraform-admin)에게 관리자 Access Entry를 자동으로 준다.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = local.net.private_app_subnet_ids
    endpoint_private_access = true # 노드는 VPC 안에서 API 서버에 접속한다
    endpoint_public_access  = true # 맥의 kubectl이 접속한다
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# 노드와 파드는 EKS가 만든 클러스터 보안 그룹을 쓴다. 이 그룹에서 RDS(3306)로 들어오는 것을 허용한다.
# eks를 지우면 이 규칙도 같이 지워져 network 루트는 처음 상태로 돌아간다.
resource "aws_vpc_security_group_ingress_rule" "db_from_eks" {
  security_group_id            = local.net.security_group_ids["db"]
  referenced_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  description                  = "MySQL from EKS pods"
}

# ALB Controller가 인터넷용 ALB를 놓을 서브넷을 찾는 표시. network 루트 대신 여기서 붙였다 뗀다.
resource "aws_ec2_tag" "public_elb" {
  for_each    = toset(local.net.public_subnet_ids)
  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}
