# 프로젝트 안내 (에이전트용)

## 목적
클라우드/인프라 엔지니어 취업 포트폴리오. Terraform으로 AWS 인프라를 만들고, 그 위에 Spring Boot 앱을 GitHub Actions로 자동 배포한다. 진행 단계는 `README.md`, 날짜별 기록은 `docs/devlog.md`를 본다.

## 구조
- `terraform/` 인프라 코드 (VPC, 서브넷, 보안 그룹 등)
- `app/` Spring Boot 앱 (SAA 학습 노트 API, Gradle, Java 21)
- `docs/` 설계 문서와 개발 일지
- `.github/workflows/` CI/CD (예정)

## 반드시 지킬 규칙
1. **리전은 `ap-southeast-2`(시드니)만 쓴다.** 조직 SCP가 다른 리전의 지역 서비스를 거부한다. 새 AWS 작업 전에 리전부터 확인한다.
2. **요금이 나가는 리소스는 작업이 끝나면 항상 `terraform destroy`로 정리하고, AWS CLI로 삭제를 확인한 뒤 알린다.** (NAT Gateway, ALB, RDS, ECS 등) 계정은 유료 플랜이고 월 지출 한도가 있다.
3. **비밀 정보는 커밋하지 않는다.** 액세스 키, `*.tfstate`, `*.tfvars`, `.env`. 레포는 Public이다. 계정 번호도 문서에 쓰지 않는다.
4. **커밋은 하루 한 번 이상, 의미 있는 단위로.** 막힌 날도 설계 문서나 트러블슈팅 기록으로 잇는다. 메시지는 `feat:`, `fix:`, `docs:`, `chore:` 접두사를 쓴다.
5. `docs/devlog.md`에 그날 한 일, 막힌 점, 배운 점을 남긴다. 트러블슈팅은 면접 자료가 된다.
6. 원인을 추측으로 단정하지 않는다. 변수를 하나씩 바꿔 비교해서 확인한다.

## 작업 방식
- 사용자는 코딩 초보다. 한국어로, 전문 용어는 처음 나올 때 한 줄로 풀어 설명한다.
- 변경 후에는 무엇이, 왜, 어떻게 바뀌었는지 짧게 알린다.
- 비용이나 계정 설정이 걸린 결정은 먼저 묻는다. 카드 정보와 비밀번호는 사용자가 직접 입력한다.

## 자주 쓰는 명령
```bash
cd terraform && terraform fmt && terraform validate && terraform plan
terraform apply   # 확인 후 반드시 terraform destroy
cd app && docker build -t saa-notes:local .   # Docker 엔진은 colima start 필요
```

## 이 컴퓨터의 환경
- AWS CLI 프로필은 기본(`terraform-admin`), 기본 리전 `ap-southeast-2`
- Docker는 Colima 사용 (`colima start` / `colima stop`)
- Git 커밋 이메일은 이 레포에 GitHub noreply 주소로 설정되어 있다. 실제 이메일은 푸시가 거부된다(GH007).
