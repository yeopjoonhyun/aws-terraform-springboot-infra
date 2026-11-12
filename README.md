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
| Cloud | AWS (VPC, ECS, ECR, ALB, RDS, CloudWatch, IAM) |
| App | Spring Boot, Docker |
| CI/CD | GitHub Actions |

## 진행 단계
- [x] 1단계: 프로젝트 세팅, Terraform 기본 구성
- [x] 2단계: 네트워크(VPC, 서브넷 6개, 인터넷 게이트웨이, 퍼블릭 라우팅, 보안 그룹 3개)
- [x] 3단계: Spring Boot 앱 Docker화, ECR 업로드 ([문서](docs/03-app-docker.md))
- [x] 4단계: ECS Fargate + ALB 배포 ([문서](docs/04-ecs-alb.md))
- [ ] 5단계: Terraform 다지기 (S3 원격 state와 잠금, 루트 분리, 모듈)
- [ ] 6단계: 데이터 계층 (RDS MySQL, Secrets Manager)
- [ ] 7단계: GitHub Actions CI/CD (OIDC)
- [ ] 8단계: 고가용성과 관측 (멀티 AZ, 자동 확장, 경보)
- [ ] 9~10단계 (확장, 진행 여부 미정): EKS 전환, GitOps와 모니터링
- [ ] 마무리: 삭제 순서 문서화, 아키텍처 그림, 회고

자세한 계획과 순서를 정한 이유는 [로드맵](docs/roadmap.md)에 있습니다.

## 폴더 구조
```
terraform/   # 인프라 코드
app/         # Spring Boot 애플리케이션
docs/        # 설계 문서, 개발 일지, 트러블슈팅 기록
.github/     # GitHub Actions 워크플로
```

## 비용 관리
실습이 끝나면 `terraform destroy`로 리소스를 삭제합니다. NAT Gateway, ALB, RDS는 켜두는 동안 요금이 발생합니다.
