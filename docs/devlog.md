# 개발 일지

매일 한 일, 배운 것, 막힌 것을 짧게 남깁니다.

## 2026-11-07
- 한 일: 프로젝트 주제 결정, 레포 구조와 README 작성
- 배운 것: IaC(Infrastructure as Code)의 개념, .gitignore로 tfstate·비밀값을 제외해야 하는 이유
- 다음 할 일: Terraform 설치, AWS CLI 설정

## 2026-11-07 (2)
- 한 일: GitHub 레포 생성과 첫 푸시, Terraform·AWS CLI 설치, 환경 세팅 문서 작성
- 막힌 것: 푸시 시 `GH007` 에러(비공개 이메일 노출 차단)
- 해결: 커밋 이메일을 GitHub noreply 주소로 변경 후 재푸시
- 배운 것: 잔디는 커밋 이메일이 GitHub 계정과 연결되어야 하고, 기본 브랜치에 올라간 커밋만 집계된다
- 다음 할 일: AWS 루트 MFA, Budgets 알림, IAM 사용자 생성, `aws configure`

## 2026-11-08
- 한 일: AWS 계정 생성, MFA 확인, IAM 사용자(`terraform-admin`) 생성, CLI 연결, Terraform으로 VPC 코드 작성 (`init`, `validate`, `plan` 통과)
- 막힌 것: 이 계정은 Builder ID 기반이라 콘솔 메뉴에 "보안 자격 증명"이 없었다. 프로필 관리 화면에서 MFA가 이미 등록된 것을 확인했다.
- 배운 것: IAM 사용자는 고정 신분증, 역할은 잠깐 빌리는 권한 묶음이다. `terraform plan`은 실제로 만들지 않고 변경 계획만 보여준다.
- 다음 할 일: `terraform apply`로 VPC 생성 확인 후 `destroy`, 서브넷과 인터넷 게이트웨이 추가
