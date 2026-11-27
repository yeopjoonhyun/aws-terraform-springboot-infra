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
| 파드 종료 | `preStop`에서 15초 대기 | 없으면 축소와 배포 때 ALB가 내려가는 파드로 요청을 보내 실패가 났다. 아래 실측 |
| 지표 노출 | 관리 포트 8081 (EKS에서만) | Ingress는 8080만 내보내므로 `/actuator/prometheus`가 인터넷에 열리지 않는다. ALB와 쿠버네티스 상태 검사는 8080의 `/livez`, `/readyz`를 쓴다. ECS는 설정이 그대로다 |
| Slack 웹훅 | SSM Parameter Store SecureString `/saa-notes/slack-webhook` | 무료(표준 파라미터). 이름은 `aws`, `ssm`으로 시작할 수 없다(처음 정한 `/aws-tf-springboot/...`는 거부됐다). deploy.sh가 꺼내 쿠버네티스 Secret으로 넣고, Alertmanager는 `api_url_file`로 읽는다. 설정 파일과 Git에 주소가 남지 않는다 |
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

## 실습 결과 (2026-11-27)

시드니, EKS 1.37, `t4g.medium` 노드 2대(2a, 2b). 부하는 맥에서 `ab`로 ALB의 `/api/notes`에 보냈다. 모든 수치는 한 번씩 잰 값이다.

### 설치와 기본 검증

| 항목 | 결과 |
|---|---|
| data, eks apply (동시 실행) | 16:13:18 -> 16:24:21, 11분 3초. RDS 3개, EKS 22개 |
| `k8s/deploy.sh` | 16:27:20 -> 16:32:32, 5분 12초 (ALB Controller, 모니터링, Argo CD, Application) |
| 이미지 덮어쓰기 | Argo CD가 매니페스트의 `app` + base 태그 `69507e4`를 ECR 주소로 바꿔 배포했다 |
| 노트 API (ALB -> RDS) | 생성 201, 조회 200, 삭제 204, 삭제 후 조회 404 |
| 지표 노출 | ALB로 `/actuator/prometheus` 404. Prometheus는 두 파드의 8081을 `up`으로 수집 |
| 경보 규칙 | 4개 모두 `ok`로 로드 |

### 부하, 자동 확장, Slack 경보

| 시각 | 일 |
|---|---|
| 16:35:27 | 부하 시작 (동시 50, 15초당 약 3,000건) |
| 16:35:58 | CPU 109% (요청 250m 기준) |
| 16:36:30 | HPA 2 -> 4 |
| 16:36:58 | `SaaNotesAtMaxReplicas` pending |
| 16:39:58 | firing. Slack `[FIRING]` 메시지 16:40 도착 |
| 16:45:45~16:46:46 | 부하 중 CPU가 15% 안팎으로 내려가 HPA 4 -> 3 -> 2. **이때 51건 실패** |
| 16:46:13 | 경보 해제. Slack `[RESOLVED]` 16:50 도착 (Alertmanager가 5분 단위로 묶어 보낸다) |

12분 동안 68,461건 중 51건이 실패했다. 실패는 모두 축소 구간에 있었다. 앱 지표에는 5xx가 없었으므로 ALB에서 난 오류로 판단했다(추론, `ab`는 상태 코드를 나눠 보여 주지 않는다). 파드가 종료 신호를 받고 바로 내려가는데 ALB는 대상에서 빼기 전까지 그 파드로 요청을 보낸다.

CPU가 부하를 유지하는데도 109%에서 15% 안팎으로 내려간 것은 JVM이 코드를 최적화하기 전후의 차이로 보인다(추론, 측정하지 않았다). 차트 기본 경보 `KubeHpaMaxedOut`도 pending이 됐지만 Slack 경로에서 빠져 있어 오지 않았다(의도한 동작).

### GitOps 배포, 되돌리기, preStop 비교

부하(동시 20)를 건 채로 세 번 배포했다. 바꾼 것은 `preStop` 하나다.

| 단계 | 한 일 | 걸린 시간 | 실패 |
|---|---|---|---|
| A | 인프라 레포 main 푸시 -> CI가 이미지 `aa6c050`과 매니페스트 태그 커밋 -> Argo CD 배포 | 푸시 16:48:54 -> 교체 완료 16:52:10, 3분 16초 | **40건** (내려간 파드에 preStop 없음) |
| B | 매니페스트 레포에 `preStop` 15초 추가 | 푸시 16:52:34 -> 약 1분 20초 | 7건 (내려간 옛 파드에는 아직 preStop 없음, 비교 제외) |
| 축소 | HPA 3 -> 2 (17:00:14) | - | **0건** (preStop 있음) |
| C | 매니페스트 레포에서 A의 태그 커밋을 `git revert` -> `69507e4`로 되돌림 | 푸시 17:00:42 -> 교체 완료 17:04:22, 3분 40초 | **0건** (preStop 있는 파드 4개가 내려감) |

- 배포와 되돌리기 모두 클러스터에 명령을 내리지 않고 Git 커밋만으로 했다.
- Argo CD가 커밋을 알아채는 데 A는 약 15초, C는 약 2분 30초 걸렸다. Git 확인 주기(60초)에 지터(최대 60초)가 더해진다.
- 한계: A는 파드 2개, C는 4개가 교체됐고 각각 한 번씩만 쟀다. 그래도 같은 조건의 축소(51건 -> 0건)와 배포(40건 -> 0건)에서 같은 방향으로 바뀌었다.

### 막힌 것

- `deploy.sh`가 Application의 `Healthy`를 기다렸는데, Argo CD가 리소스를 만들기 전에도 잠깐 `Healthy`라서 ALB 주소가 빈 채로 끝났다. Deployment 생성, 롤아웃, Ingress 주소를 직접 기다리게 고쳤다.
- 첫 동기화 직후 Application이 잠깐 `Degraded`였다. HPA의 CPU 지표가 아직 `<unknown>`이던 때라 그것으로 보인다(추론). 1분 안에 `Healthy`가 됐다.
- 노트 생성이 400이었다. 요청에 필수 필드 `category`를 빠뜨렸다. 앱이 맞게 거부한 것이다.

### 정리

`k8s/teardown.sh`로 Application을 지우자 Argo CD가 Ingress까지 지웠고 ALB가 33초 만에 0개가 됐다(17:04:48 -> 17:05:21). 이어서 eks와 data를 destroy했다. destroy는 17:05:28 -> 17:14:45, 9분 17초. 최종 스냅샷과 ECR 이미지 2개를 지웠다.

destroy 뒤에 VPC CNI가 노드에 붙였던 ENI(`aws-K8S-i-...`, 연결 안 됨) 1개와, 그 ENI가 붙잡고 있던 EKS 클러스터 보안 그룹 1개가 남았다. 요금은 없지만 네트워크를 지울 때 막을 수 있어 직접 지웠다. 다음부터는 destroy 뒤에 ENI와 `eks-cluster-sg-*` 보안 그룹도 확인한다.

확인(AWS CLI): EKS 클러스터, EC2, EBS, NAT, EIP, ALB, 대상 그룹, RDS 인스턴스, 수동 스냅샷, 남은 자동 백업, RDS 관리 비밀, ECR 이미지, ECS 클러스터, ENI, EKS 보안 그룹 모두 0개. eks와 data state는 비었고 network plan은 변경 없음.
