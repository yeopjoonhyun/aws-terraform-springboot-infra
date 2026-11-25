# AWS Load Balancer Controller의 권한. 컨트롤러는 Ingress를 보고 ALB를 만든다.
# 정책 파일은 공식 저장소 v3.6.3의 docs/install/iam_policy.json 그대로다. 차트도 같은 버전을 쓴다.
# 컨트롤러가 만든 ALB는 Terraform이 모른다. destroy 전에 Ingress를 먼저 지운다 (docs/09-eks.md).
resource "aws_iam_role" "alb_controller" {
  name = "${local.cluster}-alb-controller"

  # Pod Identity: 지정한 ServiceAccount의 파드만 이 역할을 쓴다 (아래 association).
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "alb_controller" {
  name   = "aws-load-balancer-controller"
  role   = aws_iam_role.alb_controller.id
  policy = file("${path.module}/alb-controller-policy.json")
}

resource "aws_eks_pod_identity_association" "alb_controller" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.alb_controller.arn
}
