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
- Terraform 구조: `terraform/` 한 폴더(루트 1개), state는 로컬. 원격 state와 루트 분리는 아직 없음.
- 앱 DB: H2 메모리 DB. MySQL 드라이버 없음.
- 알려진 이슈: 0.25 vCPU에서 앱 기동이 약 67초 걸림 (`health_check_grace_period_seconds = 120`으로 버팀).

## 큰 그림

```txt
[A 트랙: ECS로 완성]  1~4 완료 -> 5 Terraform 다지기 -> 6 데이터 계층 -> 7 CI/CD -> 8 고가용성과 관측
[B 트랙: K8s로 확장]  9 EKS + Kustomize -> 10 GitOps와 모니터링 -> 마무리
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
| 마무리 | 리소스 삭제 순서 문서화(만든 순서의 반대: 클러스터 안 -> 클러스터 -> 데이터 -> 네트워크), 아키텍처 그림, README 정리, 회고 | 16, 17 | 0 |

## 순서를 이렇게 잡은 이유

1. Terraform 다지기를 RDS보다 먼저 한다. 지금은 state가 로컬에 있고 모든 리소스가 한 루트에 묶여 있어서, RDS를 붙이면 앱 재배포 때 DB까지 같은 state로 움직인다. CI/CD에서 Terraform을 돌리려면 state가 S3에 있어야 한다.
2. CI/CD는 데이터 계층 다음에 한다. DB 접속 정보가 Secrets Manager로 정리된 뒤에 파이프라인을 만들어야 비밀값을 GitHub에 둘 일이 없다.
3. EKS는 맨 뒤에 둔다. 켜 둔 시간만큼 요금이 나가고 그중 가장 비싸다. 앞 단계를 모두 끝내고 짧게 켰다 끈다.

## 다음에 할 일

5단계 Terraform 다지기부터 시작한다. 첫 작업은 state용 S3 버킷을 만드는 bootstrap 루트 작성이다.
