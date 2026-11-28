# AWS Terraform Spring Boot Infra

Terraform으로 AWS 인프라를 코드로 구축하고, 그 위에 Spring Boot 애플리케이션을 GitHub Actions로 자동 배포하는 프로젝트입니다.

## 목표
- AWS SAA 학습 내용을 실제 인프라 설계로 구현
- 모든 인프라를 코드(IaC)로 관리하여 재현 가능하게 구성
- 코드 푸시부터 배포까지 CI/CD 자동화

## 아키텍처 (계획)
```
사용자 → ALB → ECS(Fargate) → Spring Boot 컨테이너 → RDS(MySQL)
                                     ↑
                 GitHub Actions → ECR(이미지 저장소)
```
- 네트워크: VPC, 퍼블릭/프라이빗 서브넷(2 AZ), NAT Gateway
- 컴퓨팅: ECS Fargate + Application Load Balancer
- 데이터: RDS(프라이빗 서브넷)
- 모니터링: CloudWatch Logs / Alarms

## 기술 스택
| 분류 | 사용 기술 |
|---|---|
| IaC | Terraform |
| Cloud | AWS (VPC, ECS, EKS, ECR, ALB, RDS, CloudWatch, IAM) |
| App | Spring Boot, Docker |
| CI/CD | GitHub Actions |

## 진행 단계
- [x] 1단계: 프로젝트 세팅, Terraform 기본 구성
- [x] 2단계: 네트워크(VPC, 서브넷 6개, 인터넷 게이트웨이, 퍼블릭 라우팅, 보안 그룹 3개)
- [x] 3단계: Spring Boot 앱 Docker화, ECR 업로드 ([문서](docs/03-app-docker.md))
- [x] 4단계: ECS Fargate + ALB 배포 ([문서](docs/04-ecs-alb.md))
- [x] 5단계: Terraform 다지기 (S3 원격 state와 잠금, 루트 분리, 모듈) ([문서](docs/05-remote-state.md))
- [x] 6단계: 데이터 계층 (RDS MySQL, Secrets Manager) ([문서](docs/06-rds.md))
- [x] 7단계: GitHub Actions CI/CD ([문서](docs/07-cicd.md)). main 푸시부터 ECS 무중단 배포까지 자동, AWS 접근은 장기 키 없이 OIDC
- [x] 8단계: [고가용성과 관측](docs/08-ha-observability.md) (멀티 AZ, CPU 자동 확장 2~4개 실측, CloudWatch 경보)
- [x] 9단계: [EKS 전환](docs/09-eks.md) (ARM64 노드 2대, ALB를 통한 RDS 저장 검증)
- [x] 10단계: [GitOps와 모니터링](docs/10-gitops-monitoring.md) (Argo CD와 별도 매니페스트 레포, Prometheus 골든 시그널 경보 -> Slack, preStop으로 배포 중 실패 40건 -> 0건)
- [ ] 마무리: 삭제 순서 문서화, 아키텍처 그림, 회고

자세한 계획과 순서를 정한 이유는 [로드맵](docs/roadmap.md)에 있습니다.

## 폴더 구조
```
bootstrap/          # Terraform state를 보관할 S3 버킷 (최초 1회)
terraform/network/  # VPC, 서브넷, 보안 그룹 (전부 무료, 항상 유지)
terraform/registry/ # ECR, GitHub Actions OIDC 배포 역할 (무료, 항상 유지)
terraform/data/     # RDS MySQL, 암호는 Secrets Manager (요금 발생, 쓸 때만 켜기)
terraform/app/      # NAT, ALB, ECS (요금 발생, 쓸 때만 켜기)
terraform/eks/      # EKS, ARM64 노드, NAT (요금 발생, 쓸 때만 켜기)
k8s/                # EKS 앱 매니페스트와 배포·정리 스크립트
app/                # Spring Boot 애플리케이션
docs/        # 설계 문서, 개발 일지, 트러블슈팅 기록
.github/     # GitHub Actions 워크플로 (CI: 테스트, 빌드, Terraform 검사 / CD: ECR 푸시, ECS 배포)
```

## 비용 관리
실습이 끝나면 `terraform destroy`로 리소스를 삭제합니다. ECS 실습은 `app`을 삭제한 뒤 `data`를 정리합니다. EKS에서는 먼저 `k8s/teardown.sh`로 Ingress가 만든 ALB를 삭제한 뒤 `eks`와 `data`를 정리합니다. [ECS·EKS 정리 순서와 AWS 점검 명령](docs/teardown.md)
