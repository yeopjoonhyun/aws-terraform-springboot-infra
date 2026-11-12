# 04. ECS Fargate + ALB 배포

## 구조
```
인터넷 → ALB (퍼블릭 서브넷 a, b, 80 포트)
          → 대상 그룹 (헬스체크 /actuator/health)
             → ECS Fargate 작업 (프라이빗 앱 서브넷, 공인 IP 없음, 8080)
                → NAT Gateway (퍼블릭 a) → ECR 이미지 받기, CloudWatch Logs
```

| 파일 | 내용 |
|---|---|
| `terraform/routing.tf` | NAT Gateway(+EIP), 프라이빗 앱 라우팅 테이블 |
| `terraform/alb.tf` | ALB, 대상 그룹(target_type `ip`), HTTP 리스너 |
| `terraform/ecs.tf` | 클러스터, 로그 그룹(7일), 실행 역할, 작업 정의(ARM64, 0.25 vCPU/0.5GB), 서비스 |

## 설계 결정
- **앱은 프라이빗 서브넷**에 두고 공인 IP를 주지 않는다. 인터넷에서 들어오는 길은 ALB뿐이고, 앱은 ALB 보안 그룹에서 오는 8080만 받는다.
- **ARM64 Fargate**: 이미지를 Apple Silicon에서 arm64로 빌드했고, 시드니 기준 x86보다 vCPU 단가가 약 20% 싸다.
- **NAT 1개**(AZ a): 비용 절감. AZ a 장애 시 b의 앱도 밖으로 못 나가는 한계가 있다. 운영 환경이면 AZ마다 하나씩 둔다.
- **HTTP만**: 도메인과 ACM 인증서가 없어 443 리스너는 아직 없다.
- **헬스체크 유예 120초**: 0.25 vCPU에서는 JVM 기동이 약 68초 걸린다(로컬 4초). 유예가 없으면 기동 중 헬스체크 실패로 작업이 교체될 수 있다.
- **이미지 태그는 변수**(`image_tag`, Git 커밋 해시). ECR이 태그 불변이라 같은 태그를 다른 이미지로 덮어쓸 수 없다.

## 배포 절차
ECS는 ECR에 이미지가 있어야 작업을 띄울 수 있다. ECR 저장소도 Terraform이 만들기 때문에 처음에는 두 단계로 나눈다.
```bash
cd terraform
TAG=aa3e184   # 배포할 이미지 태그
# 1) ECR만 먼저 생성
terraform apply -var image_tag=$TAG -target=aws_ecr_repository.app -target=aws_ecr_lifecycle_policy.app
# 2) 이미지 푸시 (zsh에서는 반드시 ${REPO}처럼 중괄호를 쓴다)
REPO=$(aws ecr describe-repositories --repository-names aws-tf-springboot-app --query 'repositories[0].repositoryUri' --output text)
aws ecr get-login-password | docker login -u AWS --password-stdin ${REPO%%/*}
docker tag saa-notes:local "${REPO}:${TAG}" && docker push "${REPO}:${TAG}"
# 3) 나머지 전체 생성
terraform apply -var image_tag=$TAG
terraform output -raw alb_url
# 4) 확인이 끝나면 반드시 삭제
terraform destroy -var image_tag=$TAG
```

## 검증 결과 (2026-11-12)
- 리소스 37개 생성 약 3분, 생성 후 약 3분 뒤 대상 상태 `healthy`
- ALB 주소로 헬스체크 UP, 생성 201, 조회 200, 빈 제목 400, 없는 노트 404
- 앱 작업의 네트워크 인터페이스: 사설 IP만 있고 공인 IP 없음
- 삭제 후 ALB, NAT, EIP, ECS 클러스터, ECR, VPC, 로그 그룹, IAM 역할 모두 0개 확인
- 비용: 약 10분 사용, ALB·NAT는 1시간 단위 과금이라 약 $0.12
