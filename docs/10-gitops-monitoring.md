# 10단계 GitOps와 모니터링

9단계에서는 맥에서 `kubectl apply`로 앱을 올렸다. 10단계에서는 배포를 Git 커밋으로만 한다. Argo CD가 매니페스트 레포를 지켜보고 클러스터를 그 내용에 맞춘다. Prometheus가 앱의 골든 시그널을 모으고, 기준을 넘으면 Alertmanager가 Slack으로 알린다.

## 배포 흐름

```
인프라 레포 main 푸시
  -> GitHub Actions: 테스트, ARM64 이미지 빌드, ECR 푸시
  -> 매니페스트 레포 base/kustomization.yaml 의 newTag 를 커밋 해시로 바꿔 커밋 (배포 키)
  -> Argo CD (1분마다 Git 확인): 새 태그로 Deployment 갱신
  -> 쿠버네티스: 파드를 하나씩 교체 (readiness 통과한 파드만 ALB 대상)
```

- 매니페스트 레포: [aws-tf-springboot-manifests](https://github.com/yeopjoonhyun/aws-tf-springboot-manifests) (Public)
- 되돌리기: 매니페스트 레포에서 태그 커밋을 `git revert` 한다. 클러스터에 직접 손대지 않는다.
- CI가 매니페스트 레포에 쓰는 권한은 그 레포 하나에만 걸린 배포 키다 (GitHub 비밀값 `MANIFESTS_DEPLOY_KEY`). 개인 토큰을 쓰지 않는다.
- EKS가 꺼져 있어도 CI는 태그를 커밋한다. 다음에 클러스터를 켜면 Argo CD가 최신 태그로 바로 맞춘다. 단, 작업을 마칠 때 ECR 이미지를 지우므로 다시 켤 때는 main에 푸시해 이미지를 다시 올린다.

## 설계 결정

| 결정 | 고른 것 | 이유 |
|---|---|---|
| 매니페스트 위치 | 별도 Public 레포 | 앱 코드와 배포 상태의 권한과 이력을 나눈다. 배포 이력이 매니페스트 레포 커밋 목록으로 남는다 |
| ECR 주소 | Git에 두지 않고 Argo CD Application이 이름만 덮어씀 | 주소에 계정 번호가 있다. Application은 클러스터에만 있다 |
| 태그 위치 | overlay가 아니라 base | Argo CD의 이미지 덮어쓰기(`kustomize edit set image app=<ECR>`)는 같은 층의 `newTag`를 지운다. 로컬에서 kustomize 5.8로 재현했다. 층을 나누면 태그가 남는다 |
| 태그 형식 | `newTag: "abc1234"` 따옴표 | 따옴표가 없으면 `0000000` 같은 해시를 YAML이 숫자로 읽어 kustomize가 거부한다 (실제로 났던 에러) |
| Deployment `replicas` | 적지 않음 | 적으면 HPA가 늘린 개수를 Argo CD selfHeal이 Git 값으로 되돌린다 |
| 지표 노출 | 관리 포트 8081 (EKS에서만) | Ingress는 8080만 내보내므로 `/actuator/prometheus`가 인터넷에 열리지 않는다. ALB와 쿠버네티스 상태 검사는 8080의 `/livez`, `/readyz`를 쓴다. ECS는 설정이 그대로다 |
| Slack 웹훅 | SSM Parameter Store SecureString | 무료(표준 파라미터). deploy.sh가 꺼내 쿠버네티스 Secret으로 넣고, Alertmanager는 `api_url_file`로 읽는다. 설정 파일과 Git에 주소가 남지 않는다 |
| 경보 대상 | `namespace="saa-notes"`만 Slack | 차트 기본 경보는 버린다. EKS가 숨긴 제어 플레인 수집(etcd, scheduler 등)은 꺼서 거짓 경보를 막았다 |
| 차트 버전 | Argo CD 10.18.0, kube-prometheus-stack 93.2.2 | 둘 다 2주 이상 지난 버전 (최신은 1~2일 전 출시) |
| 뺀 것 | Grafana, External Secrets, ApplicationSet, Dex | 지금 쓰지 않는다. 대시보드는 Prometheus 화면으로, DB 비밀은 deploy.sh가 넣는다 |

## 골든 시그널 경보 (매니페스트 레포 `base/prometheusrule.yaml`)

| 신호 | 경보 | 조건 |
|---|---|---|
| 오류 | SaaNotesHighErrorRate | 5xx 비율 5% 초과 2분 |
| 응답 시간 | SaaNotesHighLatency | p95 1초 초과 5분 |
| 포화도 | SaaNotesAtMaxReplicas | HPA가 최대(4개)에 3분 머묾 |
| 트래픽 | SaaNotesDown | 준비된 파드 0개 1분 |

상태 검사(`/livez`, `/readyz`)는 사용자 요청이 아니라 오류율과 응답 시간 계산에서 뺀다. 설정은 `amtool check-config`, 규칙은 `promtool check rules`로 로컬에서 검사했다.

## 실습 순서

1. Slack 웹훅을 만들어 SSM에 넣는다 (최초 1회, 사용자가 직접 입력).
   ```zsh
   read -s "URL?Slack 웹훅 주소: " && aws ssm put-parameter --region ap-southeast-2 --name /saa-notes/slack-webhook --type SecureString --value "$URL" && unset URL
   ```
2. main에 푸시해 이미지와 매니페스트 태그를 준비한다 (CI).
3. `terraform/data`, `terraform/eks` apply (9단계와 같음).
4. `k8s/deploy.sh`. ALB Controller, 모니터링, Argo CD를 깔고 Application을 등록한다.
5. 검증: ALB로 노트 API, Prometheus 수집 대상과 규칙, 부하로 HPA 확장과 Slack 경보, main 푸시로 자동 배포, `git revert`로 되돌리기.
6. `k8s/teardown.sh` -> eks, data destroy -> AWS CLI로 0개 확인 -> ECR 이미지 삭제.
