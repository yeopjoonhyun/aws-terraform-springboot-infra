output "cluster_name" {
  description = "aws eks update-kubeconfig --name 에 쓴다"
  value       = aws_eks_cluster.main.name
}

output "vpc_id" {
  description = "ALB Controller 설치(helm)에 넘긴다"
  value       = local.net.vpc_id
}
