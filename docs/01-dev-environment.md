# 01. 개발 환경 세팅

## 설치한 도구
| 도구 | 버전 | 용도 |
|---|---|---|
| Terraform | 1.17.1 | 인프라를 코드로 정의하고 생성/삭제 |
| AWS CLI | 2.39.6 | 터미널에서 AWS 계정과 통신 |
| GitHub CLI | 2.103.3 | 터미널에서 GitHub 레포 관리 |

설치는 Homebrew로 진행했습니다.

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform awscli gh
```

## AWS 계정 보안 원칙
1. **루트 계정은 일상 작업에 쓰지 않는다.** 루트 계정에는 MFA(2단계 인증)만 걸고 잠가둔다.
2. **작업용 IAM 사용자를 따로 만든다.** 필요한 권한만 부여한다.
3. **액세스 키는 절대 Git에 올리지 않는다.** `aws configure`로 로컬(`~/.aws/credentials`)에만 저장한다.
4. **비용 알림을 먼저 건다.** AWS Budgets로 월 예산 초과 전에 메일을 받는다.

## 체크리스트
- [x] 로그인 계정 MFA 설정 (Builder ID 기반 계정, TOTP 인증 앱)
- [ ] AWS Budgets 월 예산 알림 설정
- [x] 작업용 IAM 사용자 생성 (`terraform-admin`, 현재 AdministratorAccess)
- [x] `aws configure`로 CLI 연결 (리전: ap-northeast-2)
- [x] `aws sts get-caller-identity`로 연결 확인

## 메모
- 계정은 무료 플랜으로 가입 (크레딧 US$100, 약 6개월). 크레딧 소진 또는 기간 종료 시 서비스 접근이 종료되는 방식이라 예상치 못한 청구 위험이 낮다.
- 학습 초기라 `AdministratorAccess`를 부여했다. 이후 필요한 권한만 남기도록 줄이는 작업을 별도 문서로 남길 예정이다.
