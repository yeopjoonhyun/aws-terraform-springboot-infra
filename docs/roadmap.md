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
3. 월 지출 한도는 $20 (크레딧 $100). 비싼 단계는 짧게 켰다 끈다.
4. 비밀 정보(액세스 키, `*.tfstate`, `*.tfvars`, `.env`, 계정 번호)는 커밋하지 않는다.
5. 커밋 접두사는 `feat:`, `fix:`, `docs:`, `chore:`. 그날 한 일, 막힌 점, 배운 점을 devlog에 남긴다.
6. 원인은 추측하지 않고 변수를 하나씩 바꿔 비교해서 확인한다.

## 현재 상태 (2026-11-12)

- 완료: 1~4단계. VPC, 서브넷 6개(public 2, private-app 2, private-db 2), IGW, 보안 그룹 3개(alb, app, db), Spring Boot 앱(saa-notes, Java 21, Spring Boot 4.1.2, Alpine 베이스), ECR(IMMUTABLE 태그, 커밋 SHA), ECS Fargate(ARM64, 0.25 vCPU) + ALB + NAT Gateway, CloudWatch 로그 그룹, 실행 역할.
- 4단계 리소스는 destroy로 정리 완료. 현재 AWS 요금 0.
- Terraform 구조(2026-11-13 갱신): `bootstrap/`(state 버킷), `terraform/network/`(무료, 유지), `terraform/app/`(요금 발생)로 루트를 나눴고 state는 S3에 둔다. data 루트(RDS)는 6단계에서 추가한다.
- 앱 DB: H2 메모리 DB. MySQL 드라이버 없음.
- 알려진 이슈: 0.25 vCPU에서 앱 기동이 약 67초 걸림 (`health_check_grace_period_seconds = 120`으로 버팀).

## 큰 그림

```txt
[A 트랙: ECS로 완성]  1~4 완료 -> 5 Terraform 다지기 -> 6 데이터 계층 -> 7 CI/CD -> 8 고가용성과 관측
[B 트랙: K8s로 확장]  9 EKS + Kustomize -> 10 GitOps와 모니터링 -> 11 데이터 복구(PITR) -> 마무리
```

같은 앱을 먼저 ECS로 끝까지 완성한 뒤 EKS로 옮긴다. 두 방식을 비교해서 설명할 수 있게 되는 것이 포트폴리오의 핵심이다.
(B 트랙을 진행할지는 사용자가 아직 확정하지 않았다. 시작 전에 확인한다.)

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

## 순서를 이렇게 잡은 이유

1. Terraform 다지기를 RDS보다 먼저 한다. 지금은 state가 로컬에 있고 모든 리소스가 한 루트에 묶여 있어서, RDS를 붙이면 앱 재배포 때 DB까지 같은 state로 움직인다. CI/CD에서 Terraform을 돌리려면 state가 S3에 있어야 한다.
2. CI/CD는 데이터 계층 다음에 한다. DB 접속 정보가 Secrets Manager로 정리된 뒤에 파이프라인을 만들어야 비밀값을 GitHub에 둘 일이 없다.
3. EKS는 맨 뒤에 둔다. 켜 둔 시간만큼 요금이 나가고 그중 가장 비싸다. 앞 단계를 모두 끝내고 짧게 켰다 끈다.

## 다음에 할 일

5단계 Terraform 다지기 진행 중. state용 S3 버킷(bootstrap)과 backend 연결은 끝났다(2026-11-13, `docs/05-remote-state.md`). 루트 분리(network / app)도 코드와 network apply까지 끝났다(S3 저장 확인). 남은 것은 app 루트를 한 번 실제로 apply해서 분리가 동작하는지 검증(약 $0.12)하고 destroy하는 것, 그리고 반복 패턴을 모듈로 정리하는 것이다.
