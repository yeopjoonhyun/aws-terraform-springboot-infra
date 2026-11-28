# aws-terraform-springboot-infra 로드맵

작성일: 2026-11-12
저장소: https://github.com/yeopjoonhyun/aws-terraform-springboot-infra (Public)
목표 범위: 수업 교안의 17개 주제를 이 프로젝트 하나로 직접 구현하는 것.
(교안은 내부 전용 자료라 내용을 저장소에 옮기지 않는다. 직접 한 작업만 기록한다.)

## 이 문서를 받은 세션에게

- 사용자는 코딩 초보다. 한국어로 설명하고, 전문 용어는 처음 나올 때 한 줄로 풀어 준다.
- 프로젝트 파일은 사용자의 Mac에 있다 (Apple Silicon, Docker는 Colima). 저장소의 `CLAUDE.md`와 `docs/devlog.md`를 먼저 읽는다.
- 요금이 나가는 작업(apply, 리소스 생성)은 실행 전에 반드시 사용자에게 묻는다.

## 지켜야 할 조건

1. 리전은 `ap-southeast-2`(시드니)만 쓴다. 조직 SCP가 다른 리전을 거부한다.
2. 요금이 나가는 단계는 매번 apply, 확인, destroy 순서로 진행하고, AWS CLI로 삭제를 확인한다.
3. 개인 AWS 프로젝트의 월 지출 한도는 $40이다. 11월 24일에 $20에서 올렸다. 요금이 나가는 리소스는 검증에 필요한 동안만 켠다. [지출 한도 조사 기록](devlog.md#2026-11-24)
4. 비밀 정보(액세스 키, `*.tfstate`, `*.tfvars`, `.env`, 계정 번호)는 커밋하지 않는다.
5. 커밋 접두사는 `feat:`, `fix:`, `docs:`, `chore:`. 그날 한 일, 막힌 점, 배운 점을 devlog에 남긴다.
6. 원인은 추측하지 않고 변수를 하나씩 바꿔 비교해서 확인한다.

## 현재 상태 (2026-11-28)

- 1~10단계를 완료했다. 같은 Spring Boot 노트 앱을 ECS Fargate와 EKS에 각각 배포했고, 두 환경에서 RDS MySQL에 노트를 저장하고 조회했다. 로컬 기본 프로필은 H2를 쓴다. [RDS 구성](06-rds.md), [EKS 검증과 ECS 비교](09-eks.md)
- Terraform 실행 단위를 `bootstrap`, `network`, `registry`, `data`, `app`, `eks`로 분리했다. `bootstrap`은 state 저장용 S3 버킷을 만들고, 나머지 루트는 그 버킷에 state를 저장한다. 두 앱 환경은 같은 프라이빗 서브넷 기본 경로에 NAT를 연결하므로 한 번에 하나만 켠다. [Terraform 구조](../CLAUDE.md)
- GitHub Actions는 OIDC로 임시 AWS 권한을 받아 ARM64 이미지를 ECR에 올린다. EKS에서는 CI가 별도 매니페스트 저장소의 이미지 태그를 갱신하면 Argo CD가 배포한다. HPA로 파드 2개가 4개까지 늘어나는 것과 Prometheus 경보가 Slack에 도착하는 것을 확인했다. [GitOps·모니터링 실측](10-gitops-monitoring.md#실습-결과-2026-11-27)
- 11월 27일 실습 후 EKS, EC2, EBS, NAT, 공인 IP, ALB, RDS, 스냅샷, ECR 이미지가 모두 0개였다. EKS와 RDS의 Terraform state도 비었고, 네트워크 실행 계획에 변경 사항이 없었다. [마지막 AWS 정리 확인](10-gitops-monitoring.md#정리)

## 큰 그림

```txt
[A 트랙: ECS로 완성]  1~4 완료 -> 5 Terraform 다지기 -> 6 데이터 계층 -> 7 CI/CD -> 8 고가용성과 관측
[B 트랙: K8s로 확장]  9 EKS + Kustomize -> 10 GitOps와 모니터링 -> 11 데이터 복구(PITR) -> 마무리
```

같은 앱을 먼저 ECS로 끝까지 완성한 뒤 EKS로 옮긴다. 두 방식을 비교해서 설명할 수 있게 되는 것이 포트폴리오의 핵심이다.

## 단계별 상세

| 단계 | 할 일 | 교안 주제 번호 | 비용 |
| --- | --- | --- | --- |
| 1~4 (완료) | 네트워크, Docker, ECR, ECS Fargate, ALB, NAT | 03, 05, 09 일부 | 완료 |
| 5. Terraform 다지기 | state를 S3 원격 저장소로 이전하고 잠금 설정. 루트를 bootstrap / network / data / app으로 분리하고 `terraform_remote_state`로 연결. 공통 패턴은 모듈로 | 13 | 거의 0 |
| 6. 데이터 계층 | RDS MySQL을 private-db 서브넷에. 암호는 Secrets Manager, ECS 작업 정의의 `secrets`로 주입. 작업 역할(앱이 쓰는 권한) 추가. 앱에 MySQL 드라이버와 프로필 추가. 삭제 방지, 백업 보존, 최종 스냅샷 설정. 선택: 첨부 파일용 S3 + 프리사인 URL + S3 게이트웨이 엔드포인트, ElastiCache cache-aside | 02, 04, 07 | RDS 켜 둔 시간만큼 |
| 7. CI/CD | GitHub Actions: PR마다 테스트, main 머지 시 ARM 이미지 빌드, SHA 7자리 태그로 ECR 푸시, ECS 배포. AWS 접근은 OIDC 역할(저장소와 브랜치를 신뢰 조건에). PR에 `terraform plan` 결과 남기기. 서드파티 액션 버전 고정, 브랜치 보호 | 02, 08 | GitHub 무료 범위 |
| 8. 고가용성과 관측 | 작업 2개를 2개 AZ에. CPU 대상 추적 자동 확장. CloudWatch 경보(ALB 5xx, 응답 시간, RDS CPU) -> SNS -> Lambda -> Slack. 기동 시간 개선(0.5 vCPU 비교, JVM 옵션). 선택: Route 53 도메인 + ACM으로 HTTPS, 80 -> 443 리다이렉트, ECS 블루/그린 배포 | 06, 09, 15 | 도메인은 연 단위 별도 비용 |
| 9. EKS 전환 | EKS를 별도 Terraform 루트로. 관리형 Node Group, Access Entry, 애드온(VPC CNI, CoreDNS, kube-proxy, Pod Identity Agent, EBS CSI, metrics-server), Pod Identity, ALB Controller. 서브넷에 ELB 태그. 매니페스트 저장소에 Kustomize base / overlay, Deployment, Service, Ingress, Probe, requests/limits, HPA | 10, 11, 12 | 가장 비쌈. 클러스터 + 노드 + NAT |
| 10. GitOps와 모니터링 | Argo CD 설치. CI는 매니페스트 저장소의 `images.newTag`만 바꾸고 배포는 Argo CD가 담당. 되돌리기는 `git revert`. External Secrets로 Secrets Manager 연결. kube-prometheus-stack, ServiceMonitor, PrometheusRule로 골든 시그널(요청 수, 오류율, 응답 시간, 포화도) 경보, Alertmanager -> Slack. k6 부하로 HPA 확인 | 14, 15 | 9단계와 같음 |
| 11. 데이터 복구 실습 (PITR) | 실수로 지운 노트를 RDS 자동 백업의 특정 시점 복원(PITR)으로 되살린다. 기존 노트 앱과 data 루트를 그대로 쓴다. 복원은 별도 인스턴스로 하고 앱의 DB 주소만 바꿔 API로 검증한다. 복구 시간(RTO)과 잃은 데이터(RPO)를 실측해 기록한다. 12월 19일 이후 진행. [상세 계획](#11단계-데이터-복구-실습-pitr-계획) | 교안 외 추가 실습 | RDS 2대 + 앱을 켜 둔 시간만큼 |
| 마무리 | 리소스 삭제 순서 문서화(만든 순서의 반대: 클러스터 안 -> 클러스터 -> 데이터 -> 네트워크), 아키텍처 그림, README 정리, 회고 | 16, 17 | 0 |

## 11단계 데이터 복구 실습 (PITR) 계획

작성일: 2026-11-27. 계획만 적었다. 실습은 2026-12-19(재경관리사 시험) 이후에 한다.

### 목표

실수로 지운 데이터를 되살리고, 앱에서 다시 조회되는지 확인한다. 새 앱이나 DB를 만들지 않고 6단계의 노트 앱과 RDS MySQL(`terraform/data`)을 그대로 쓴다. PITR(Point-In-Time Recovery)은 자동 백업 보관 기간 안에서 원하는 시점(초 단위)으로 DB를 복원하는 기능이다. 지금 RDS는 자동 백업을 7일 보관하므로(`backup_retention_period = 7`) 추가 설정 없이 쓸 수 있다.

### 순서

1. **삭제 전 준비.** data 루트와 앱을 켠다. 테스트 노트 A, B를 API로 저장하고 응답의 id를 기록한다. RDS의 `LatestRestorableTime`(복원 가능한 가장 최근 시점, 보통 현재보다 5분쯤 늦다)을 조회해 저장 시점 이후로 넘어갔는지 확인한다. 넘어가야 그 시점이 자동 백업으로 복원 가능하다.
2. **사고 재현.** 삭제 직전 시각(UTC, 초 단위)을 기록하고 노트 A를 API로 삭제한다. 조회가 404인지 확인한다. 이어서 노트 C를 저장한다. C는 복원 시점 이후에 생긴 데이터라 복원 DB에 없어야 한다(RPO 측정용).
3. **복원.** 복구 시작 시각을 기록하고, 삭제 직전 시각으로 별도 인스턴스를 복원한다(`restore-db-instance-to-point-in-time`). 원본은 그대로 둔다. 서브넷 그룹과 보안 그룹을 원본과 같게 지정한다. 지정하지 않으면 기본 VPC에 만들어져 앱이 접속할 수 없다. 복원 인스턴스가 `available`이 된 시각(DB 복원 완료)을 기록한다.
4. **앱 연결과 검증.** 실습용 앱의 `DB_HOST`만 복원 인스턴스 주소로 바꿔 재배포한다. 바꾸는 방법(ECS 작업 정의 또는 EKS Secret)은 실습 전에 정한다. 다음을 확인하고 API 검증이 처음 성공한 시각(앱 사용 가능)을 기록한다.
   - 삭제됐던 노트 A가 다시 조회된다.
   - 노트 B가 그대로 있다.
   - 노트 C는 없다(복원 시점 이후 데이터 누락).
   - 새 노트 D가 저장되고 조회된다.
5. **기록.** 복구 시작부터 DB 복원 완료까지, 복구 시작부터 API 검증 성공까지(RTO) 걸린 시간을 나눠 적는다. 누락된 데이터(C)와 그 이유(RPO)를 적는다. 절차와 실측은 `docs/11-pitr.md`에 남기고 README에서 링크한다. devlog에도 남긴다.
6. **정리.** 앱 -> 복원 인스턴스 -> data 루트 순서로 지운다. 복원 인스턴스는 Terraform이 모르는 리소스라 CLI로 지운다(최종 스냅샷 없이, 자동 백업 보존 없이). AWS CLI로 `aws-tf-springboot` 이름의 RDS 인스턴스, 수동 스냅샷, 남은 자동 백업(`describe-db-instance-automated-backups`), 앱 리소스(NAT, ALB, ECS 또는 EKS)가 모두 0개인지 확인한다.

### 실습 전에 확인할 것

- 리전은 `ap-southeast-2`만 쓴다. 지출 한도($40)에 걸리면 SCP가 RDS 생성을 막는다(2026-11-24 기록). 복원도 RDS 생성이라 같은 제한을 받는다.
- 요금이 나가는 단계(data apply, 앱 apply, 복원)는 사용자 확인을 받은 뒤 시작한다. 예상: RDS `db.t4g.micro` 2대(시간당 약 $0.025씩)와 앱. 앱을 ECS로 하면 NAT와 ALB, EKS로 하면 클러스터와 노드 요금이 더 붙는다. 실습 직전에 요금표로 다시 계산한다.
- 복원 인스턴스는 백업 시점의 DB 암호를 쓴다. RDS 관리 암호는 7일마다 바뀌므로, 실습 중에 바뀌지 않았는지 Secrets Manager의 마지막 교체 시각을 확인한다.
- 복원 인스턴스는 원본의 삭제 방지 설정을 따르지 않을 수 있다. 정리할 때 막히지 않게 삭제 방지를 끈 상태로 만든다.

## 시험 기간 일일 작업 (2026-11-28 ~ 2026-12-18)

작성일: 2026-11-27. 재경관리사 시험(12/19)까지 GitHub 잔디를 매일 채우기 위한 목록이다. 모두 AWS 요금이 들지 않고 하루 20~30분이면 끝난다. 결과물은 마무리 단계와 면접 준비에 그대로 쓴다.

- 하루에 위에서부터 한 항목씩 한다. "오늘 할일 가자"라고 하면 체크되지 않은 첫 항목을 진행한다.
- 끝나면 `[x]`로 바꾸고 날짜를 적는다. 결과물과 이 체크를 같은 커밋에 넣는다.
- 커밋은 그날 안에 main에 푸시한다. 잔디는 KST 날짜 기준으로 확인한다.
- 빈 커밋이나 의미 없는 변경으로 채우지 않는다. 바쁜 날은 항목을 반으로 나눠도 된다.

| # | 작업 | 결과물 | 커밋 예시 | 완료 |
|---|---|---|---|---|
| 1 | 로드맵 현재 상태 갱신 (지출 한도 $40, "현재 상태", "다음에 할 일") | `docs/roadmap.md` | `docs: 로드맵 현재 상태 갱신` | [x] 2026-11-28 |
| 2 | 리소스 삭제 순서와 점검 명령 정리 (클러스터 안 -> 클러스터 -> 데이터 -> 네트워크, ENI와 EKS 보안 그룹 포함) | [정리 절차](teardown.md) | `docs: 리소스 삭제 순서와 점검 명령` | [x] 2026-11-28 |
| 3 | ECS 아키텍처 그림 | [ECS 아키텍처](ecs-architecture.md)와 README 링크 | `docs: ECS 아키텍처 다이어그램` | [x] 2026-11-28 |
| 4 | EKS + GitOps 아키텍처 그림 (인프라 레포, 매니페스트 레포, Argo CD, Prometheus, Slack) | `docs/` 그림과 README 링크 | `docs: EKS GitOps 아키텍처 다이어그램` | [ ] |
| 5 | 회고: 1~2단계 (개발 환경, 네트워크) | `docs/retrospective.md` | `docs: 1~2단계 회고` | [ ] |
| 6 | 회고: 3~4단계 (Docker, ECS) | 같은 파일 | `docs: 3~4단계 회고` | [ ] |
| 7 | 회고: 5~6단계 (Terraform 다지기, RDS) | 같은 파일 | `docs: 5~6단계 회고` | [ ] |
| 8 | 회고: 7~8단계 (CI/CD, 고가용성) | 같은 파일 | `docs: 7~8단계 회고` | [ ] |
| 9 | 회고: 9~10단계 (EKS, GitOps) | 같은 파일 | `docs: 9~10단계 회고` | [ ] |
| 10 | 트러블슈팅 모음 1: 계정·권한 (SCP와 지출 한도, OIDC sub 형식, SSM 예약 이름) | `docs/troubleshooting.md` | `docs: 트러블슈팅 - 계정과 권한` | [ ] |
| 11 | 트러블슈팅 모음 2: 배포 (Argo CD 태그 소실, YAML 숫자 태그, Healthy 대기, HPA와 replicas) | 같은 파일 | `docs: 트러블슈팅 - 배포` | [ ] |
| 12 | 트러블슈팅 모음 3: 운영 (ALB와 preStop, ab 멈춤, 새 ALB DNS 조회) | 같은 파일 | `docs: 트러블슈팅 - 운영` | [ ] |
| 13 | 면접 예상 질문과 답 (ECS와 EKS 비교, GitOps를 고른 이유, 비용 관리) | `docs/interview.md` | `docs: 면접 예상 질문 정리` | [ ] |
| 14 | 앱 테스트 보강: `/livez`, `/readyz`, 관리 포트 분리 | `app/src/test/` | `test: 상태 검사와 관리 포트 검증` | [ ] |
| 15 | 11단계 PITR 실습 명령 초안 (복원 명령, 측정 방법, 정리 명령) | `docs/11-pitr.md` 초안 | `docs: PITR 실습 절차 초안` | [ ] |
| 16 | README 정리 (한눈에 보는 결과, 실측 숫자, 그림 링크) | `README.md` | `docs: README 결과 요약` | [ ] |

14번은 코드 변경이라 CI가 돌고 ECR에 이미지가 올라간다. 그날 작업을 마칠 때 이미지를 지운다 (CLAUDE.md 요금 점검).

## 순서를 이렇게 잡은 이유

1. 처음에는 state가 로컬에 있고 모든 리소스가 한 루트에 묶여 있었다. RDS를 붙이기 전에 state를 S3로 옮기고 루트를 나눠서 앱을 재배포할 때 DB가 같은 실행 계획에 들어가지 않도록 했다.
2. CI/CD는 데이터 계층 다음에 한다. DB 접속 정보가 Secrets Manager로 정리된 뒤에 파이프라인을 만들어야 비밀값을 GitHub에 둘 일이 없다.
3. EKS는 맨 뒤에 둔다. 켜 둔 시간만큼 요금이 나가고 그중 가장 비싸다. 앞 단계를 모두 끝내고 짧게 켰다 끈다.

## 다음에 할 일

- 시험 기간의 다음 작업은 4번이다. EKS에서 GitHub Actions가 매니페스트 태그를 갱신하고 Argo CD가 배포하는 흐름과 Prometheus에서 Slack으로 경보가 전달되는 흐름을 그린다. 이후 일일 작업표에 따라 회고를 작성한다.
- 12월 19일 시험 이후 11단계 RDS 특정 시점 복원(PITR)을 실습한다. 삭제한 노트를 복원하고, 앱에서 다시 조회할 수 있을 때까지 걸린 시간과 복원 시점 이후 누락된 데이터를 측정한다. [복구 실습 계획](#11단계-데이터-복구-실습-pitr-계획)
