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

### 트러블슈팅: apply 실패 (SCP explicit deny)
- 증상: `terraform apply` 시 `UnauthorizedOperation ... with an explicit deny in a service control policy` (ec2:CreateVpc). `aws ec2 describe-vpcs` 같은 읽기 요청도 같은 이유로 거부됨.
- 원인: 이 계정은 AWS Organizations 소속이고, 조직 수준의 SCP(서비스 제어 정책)가 EC2 작업을 명시적으로 거부한다. IAM 사용자에게 `AdministratorAccess`가 있어도 SCP의 explicit deny는 이길 수 없다. (권한 평가에서 explicit deny가 항상 우선)
- 확인한 것: IAM 사용자 생성은 가능했고, `sts get-caller-identity`도 정상. 즉 자격 증명 문제가 아니라 계정 정책 문제.
- 배운 것: `terraform plan`은 코드 문법과 계획만 확인할 뿐 권한은 검증하지 않는다. 권한 문제는 `apply` 시점에야 드러난다.
- 다음 할 일: 무료 플랜의 서비스 제한 범위 확인, 플랜 업그레이드 여부 결정

## 2026-11-09
- 한 일: SCP 제한이 유지되는지 재확인(`describe-vpcs` 여전히 거부), 네트워크 설계 문서 작성(서브넷 6개, 보안 그룹 3개, 트래픽 흐름)
- 막힌 것: EC2 작업 제한이 아직 풀리지 않아 코드를 실제로 적용하지 못함
- 배운 것: 막힌 날에도 설계 문서로 진도를 낼 수 있다. 보안 그룹은 IP 대신 다른 보안 그룹을 출처로 지정하면 계층 구조를 만들 수 있다.
- 다음 할 일: 플랜 안내 확인 후 제한 해소, 서브넷/인터넷 게이트웨이 코드 작성

### 해결: SCP는 플랜이 아니라 리전 제한이었다
- 처음에는 무료 플랜의 서비스 제한이라고 추측해 유료 플랜으로 업그레이드했지만(지출 한도 $20, 크레딧 $100 유지), 업그레이드 후에도 서울 리전의 EC2는 계속 거부됐다.
- 리전을 바꿔 `describe-vpcs`를 실행해 비교했다. `ap-southeast-2`(시드니)는 성공, `ap-northeast-2`(서울)·`ap-northeast-1`(도쿄)·`us-east-1`은 같은 SCP 에러로 거부됐다.
- 결론: 이 계정의 조직 SCP는 시드니 리전만 허용한다. 원인을 가정하지 않고 변수 하나씩 바꿔 가며 비교하는 것이 진단의 핵심이었다.
- 조치: Terraform의 `aws_region` 기본값을 `ap-southeast-2`로 변경. `terraform apply`로 VPC 생성, AWS CLI로 확인, `terraform destroy`로 삭제까지 성공.
- 배운 것: 에러 메시지의 "explicit deny in a service control policy"는 권한이 아니라 계정 정책 문제이고, 리전 조건으로 걸려 있을 수 있다. 추측으로 비용이 걸린 결정(플랜 업그레이드)을 하기 전에 먼저 변수를 좁혀 확인했어야 했다.
- 다음 할 일: 서브넷과 인터넷 게이트웨이 코드 작성 (시드니 AZ: a, b, c 중 2개 사용)

### 서브넷·인터넷 게이트웨이 구현 (시드니)
- 한 일: 서브넷 6개(퍼블릭 2, 앱 프라이빗 2, DB 프라이빗 2), 인터넷 게이트웨이, 퍼블릭 라우팅 테이블 코드 작성. `apply`로 11개 리소스를 만들고 AWS CLI로 확인한 뒤 `destroy`로 모두 삭제.
- 설계 포인트: 서브넷을 `locals` 맵 하나에 정의하고 `for_each`로 반복 생성해 코드 중복을 없앴다. AZ는 하드코딩하지 않고 `aws_availability_zones` 데이터 소스에서 읽는다. 퍼블릭 서브넷에만 라우팅 테이블을 연결해 프라이빗 서브넷은 인터넷에서 직접 닿지 않는다.
- 확인한 것: 퍼블릭 서브넷만 공인 IP 자동 할당 True, 퍼블릭 라우팅 테이블에 `0.0.0.0/0 → igw`가 있고 연결된 서브넷은 2개.
- 비용: 전부 무료 리소스. 작업 후 destroy로 정리하고 0개임을 확인.
- 다음 할 일: 보안 그룹 3개(alb, app, db) 추가, 앱 Docker화
