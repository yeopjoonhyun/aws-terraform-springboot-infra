#!/usr/bin/env bash
# terraform/eks를 destroy하기 전에 실행한다.
# ALB는 Terraform이 아니라 ALB Controller가 만들었다. 클러스터를 먼저 지우면 ALB가 남아 요금이 계속 나간다.
set -euo pipefail
# Application을 먼저 지운다. 네임스페이스만 지우면 Argo CD가 Git을 보고 다시 만든다(selfHeal).
# finalizer 때문에 Argo CD가 Ingress를 포함한 앱 리소스를 다 지운 뒤에 Application이 사라진다.
kubectl -n argocd delete application saa-notes --ignore-not-found --wait=true --timeout=5m
kubectl delete namespace saa-notes --ignore-not-found --wait=true
# 컨트롤러가 ALB를 지울 때까지 기다린다 (최대 5분)
for _ in $(seq 60); do
  n=$(aws elbv2 describe-load-balancers --region ap-southeast-2 \
    --query "length(LoadBalancers[?starts_with(LoadBalancerName,'k8s-saanotes')])" --output text)
  [ "$n" = 0 ] && { echo "ALB 0개. 이제 terraform/eks를 destroy한다."; exit 0; }
  sleep 5
done
echo "ALB가 아직 남아 있다. 콘솔이나 CLI로 확인한다." >&2; exit 1
