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
- [ ] 루트 계정 MFA 설정
- [ ] AWS Budgets 월 예산 알림 설정
- [ ] 작업용 IAM 사용자 생성
- [ ] `aws configure`로 CLI 연결
- [ ] `aws sts get-caller-identity`로 연결 확인
