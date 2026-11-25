#!/usr/bin/env bash
# EKS에 앱을 올린다. 사용법: k8s/deploy.sh <이미지 태그>
# 먼저 terraform/data, terraform/eks를 apply하고, ECR에 그 태그의 이미지가 있어야 한다.
# 여러 번 실행해도 같은 결과가 된다 (helm upgrade --install, kubectl apply).
set -euo pipefail
TAG=${1:?이미지 태그(커밋 해시 7자리)를 넘긴다}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
tf() { terraform -chdir="$ROOT/terraform/$1" output -raw "$2"; }

CLUSTER=$(tf eks cluster_name)
aws eks update-kubeconfig --name "$CLUSTER" --region ap-southeast-2 >/dev/null

# ALB Controller (Terraform alb-controller.tf의 정책과 같은 v3.6.3). 권한은 Pod Identity로 받는다.
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version 3.6.3 -n kube-system \
  --set clusterName="$CLUSTER" --set region=ap-southeast-2 --set vpcId="$(tf eks vpc_id)" \
  --set serviceAccount.name=aws-load-balancer-controller --wait

# DB 접속 정보를 쿠버네티스 Secret으로 넣는다. 비밀번호는 Secrets Manager에서 바로 꺼내고 파일로 남기지 않는다.
# ponytail: 10단계에서 External Secrets로 바꾼다 (Secrets Manager가 바뀌면 자동 반영).
kubectl apply -f "$ROOT/k8s/overlays/prod/namespace.yaml" >/dev/null
CREDS=$(aws secretsmanager get-secret-value --secret-id "$(tf data db_secret_arn)" --query SecretString --output text)
kubectl -n saa-notes create secret generic app-db --dry-run=client -o yaml \
  --from-literal=DB_HOST="$(tf data db_host)" --from-literal=DB_NAME="$(tf data db_name)" \
  --from-literal=DB_USERNAME="$(jq -r .username <<<"$CREDS")" --from-literal=DB_PASSWORD="$(jq -r .password <<<"$CREDS")" \
  | kubectl apply -f - >/dev/null

# 매니페스트의 image: app 을 실제 ECR 주소로 바꿔 적용한다 (주소에 계정 번호가 있어 커밋하지 않는다).
kubectl kustomize "$ROOT/k8s/overlays/prod" \
  | sed "s#image: app\$#image: $(tf registry ecr_repository_url):$TAG#" \
  | kubectl apply -f -
kubectl -n saa-notes rollout status deploy/saa-notes --timeout=5m
echo "ALB: http://$(kubectl -n saa-notes get ingress saa-notes -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
