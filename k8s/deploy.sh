#!/usr/bin/env bash
# EKS에 플랫폼(ALB Controller, 모니터링, Argo CD)을 깔고 앱 배포를 Argo CD에 맡긴다. 사용법: k8s/deploy.sh
# 먼저 terraform/data, terraform/eks를 apply한다. 앱 버전은 매니페스트 레포 base/kustomization.yaml의 newTag를 따른다.
# 여러 번 실행해도 같은 결과가 된다 (helm upgrade --install, kubectl apply).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MANIFESTS_RAW=https://raw.githubusercontent.com/yeopjoonhyun/aws-tf-springboot-manifests/main
tf() { terraform -chdir="$ROOT/terraform/$1" output -raw "$2"; }

# 클러스터를 건드리기 전에 확인한다: 배포할 이미지가 ECR에 있는지, Slack 웹훅이 SSM에 있는지
TAG=$(curl -fsSL "$MANIFESTS_RAW/base/kustomization.yaml" | sed -n 's/.*newTag: "\([^"]*\)".*/\1/p')
aws ecr describe-images --repository-name aws-tf-springboot-app --image-ids imageTag="$TAG" >/dev/null 2>&1 \
  || { echo "ECR에 이미지 $TAG 가 없다. 인프라 레포 main에 푸시해 CI가 올리게 한다." >&2; exit 1; }
SLACK_URL=$(aws ssm get-parameter --name /saa-notes/slack-webhook --with-decryption \
  --query Parameter.Value --output text 2>/dev/null) \
  || { echo "SSM /saa-notes/slack-webhook 이 없다 (docs/10-gitops-monitoring.md)." >&2; exit 1; }

CLUSTER=$(tf eks cluster_name)
aws eks update-kubeconfig --name "$CLUSTER" --region ap-southeast-2 >/dev/null
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update eks prometheus-community argo >/dev/null
apply_secret() { kubectl create secret generic "$@" --dry-run=client -o yaml | kubectl apply -f - >/dev/null; }
ensure_ns() { kubectl create namespace "$1" --dry-run=client -o yaml | kubectl apply -f - >/dev/null; }

# 1. ALB Controller (Terraform alb-controller.tf의 정책과 같은 v3.6.3). 권한은 Pod Identity로 받는다.
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version 3.6.3 -n kube-system \
  --set clusterName="$CLUSTER" --set region=ap-southeast-2 --set vpcId="$(tf eks vpc_id)" \
  --set serviceAccount.name=aws-load-balancer-controller --wait

# 2. 모니터링. 웹훅 주소는 파일이나 Git에 남기지 않고 바로 Secret으로 넣는다.
ensure_ns monitoring
apply_secret alertmanager-slack -n monitoring --from-literal=url="$SLACK_URL"
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version 93.2.2 -n monitoring -f "$ROOT/k8s/monitoring-values.yaml" --wait

# 3. DB 접속 정보를 쿠버네티스 Secret으로 넣는다. 비밀번호는 Secrets Manager에서 바로 꺼내고 파일로 남기지 않는다.
# ponytail: Secrets Manager 값이 바뀌어도 자동 반영되지 않는다. 필요해지면 External Secrets로 바꾼다.
ensure_ns saa-notes
CREDS=$(aws secretsmanager get-secret-value --secret-id "$(tf data db_secret_arn)" --query SecretString --output text)
apply_secret app-db -n saa-notes \
  --from-literal=DB_HOST="$(tf data db_host)" --from-literal=DB_NAME="$(tf data db_name)" \
  --from-literal=DB_USERNAME="$(jq -r .username <<<"$CREDS")" --from-literal=DB_PASSWORD="$(jq -r .password <<<"$CREDS")"

# 4. Argo CD. 쓰지 않는 구성 요소(SSO, 알림, ApplicationSet)는 끈다. Git 확인 주기는 기본 3분에서 1분으로 줄인다.
helm upgrade --install argocd argo/argo-cd --version 10.18.0 -n argocd --create-namespace \
  --set dex.enabled=false --set notifications.enabled=false --set applicationSet.replicas=0 \
  --set 'configs.cm.timeout\.reconciliation=60s' --wait

# 5. 앱을 Argo CD에 맡긴다. 이후 배포는 매니페스트 레포의 커밋으로만 한다.
sed "s#ECR_REPOSITORY#$(tf registry ecr_repository_url)#" "$ROOT/k8s/argocd-app.yaml" | kubectl apply -f -
# Application의 Healthy는 Argo CD가 리소스를 만들기 전에도 잠깐 뜬다 (2026-11-27 실측). 그래서 실제 결과를 기다린다.
wait_for() { for _ in $(seq 120); do out=$(eval "$1" 2>/dev/null) && [ -n "$out" ] && { echo "$out"; return; }; sleep 5; done; echo "10분 안에 안 됨: $1" >&2; exit 1; }
wait_for "kubectl -n saa-notes get deploy saa-notes -o name" >/dev/null
kubectl -n saa-notes rollout status deploy/saa-notes --timeout=10m
ALB=$(wait_for "kubectl -n saa-notes get ingress saa-notes -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'")
echo "배포된 이미지 태그: $TAG"
echo "ALB: http://$ALB"
