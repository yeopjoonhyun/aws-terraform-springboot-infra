# EKS 관리형 애드온: 버전 호환과 업그레이드를 AWS가 맞춰 준다.
# 버전을 적지 않으면 클러스터 버전의 기본 버전이 설치된다.
# ponytail: EBS CSI는 PersistentVolume을 쓰는 앱이 생기면 추가한다 (지금 앱은 상태를 RDS에 둔다).
resource "aws_eks_addon" "this" {
  for_each = toset([
    "vpc-cni",                # 파드에 VPC IP
    "kube-proxy",             # Service 라우팅
    "coredns",                # 클러스터 안 DNS
    "eks-pod-identity-agent", # 파드에 IAM 역할 (Pod Identity)
    "metrics-server",         # HPA가 읽는 CPU 지표
  ])
  cluster_name = aws_eks_cluster.main.name
  addon_name   = each.value

  # coredns, metrics-server는 노드가 있어야 뜬다.
  depends_on = [aws_eks_node_group.main]
}
