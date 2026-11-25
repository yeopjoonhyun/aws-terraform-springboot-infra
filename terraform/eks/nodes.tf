# 관리형 노드 그룹: 파드가 실제로 도는 EC2. AWS가 생성, 교체, 업그레이드를 맡는다.
resource "aws_iam_role" "node" {
  name = "${local.cluster}-node"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",               # VPC CNI가 파드에 VPC IP를 붙인다
    "AmazonEC2ContainerRegistryReadOnly", # ECR에서 앱 이미지를 받는다
  ])
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/${each.value}"
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.cluster}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = local.net.private_app_subnet_ids # 두 AZ
  ami_type        = "AL2023_ARM_64_STANDARD"
  instance_types  = [var.node_instance_type]
  capacity_type   = "ON_DEMAND" # 계정 정책이 스팟을 거부한다

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 3
  }

  # 노드가 인터넷(ECR)에 나갈 경로와 권한이 먼저 있어야 노드가 클러스터에 붙는다.
  depends_on = [aws_iam_role_policy_attachment.node, aws_route.private_app_nat]
}
