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

## 2026-11-10
- 한 일: 보안 그룹 3개(alb, app, db)와 규칙 7개를 Terraform으로 작성. `apply`(21개 리소스)로 만들어 규칙을 AWS CLI로 확인한 뒤 `destroy`로 삭제. 2단계(네트워크) 완료.
- 설계 포인트: 규칙의 출처를 IP가 아니라 다른 보안 그룹으로 지정했다. ALB는 인터넷에서만, 앱은 ALB에서만, DB는 앱에서만 들어올 수 있어 인터넷에서 앱과 DB로 직접 닿는 길이 없다. 규칙은 `aws_vpc_security_group_ingress_rule` 같은 별도 리소스로 분리했다. 포트는 변수(`app_port`, `db_port`)로 뽑았다.
- 확인한 것: alb-sg는 80/443을 0.0.0.0/0에, app-sg는 8080을, db-sg는 3306을 각각 다른 보안 그룹에서만 받는다.
- 비용: 보안 그룹은 무료. 작업 후 destroy로 정리하고 0개임을 확인.
- 다음 할 일: Spring Boot 앱 Docker화(`app/Dockerfile`), 이후 ECR 업로드

## 2026-11-10 (2)
- 한 일: Colima와 Docker CLI 설치. SAA 학습 노트 REST API를 새로 작성(`app/`)하고 멀티 스테이지 Dockerfile 작성. 컨테이너에서 테스트, 이미지 빌드, 실행, API 호출까지 검증.
- 결정: 수업 자료와 겹치지 않도록 수업에서 배운 도구(Spring Web, JPA, Validation, Actuator, H2, Gradle)만 써서 새 앱을 만들었다.
- 설계 포인트: 빌드 단계와 실행 단계를 분리해 최종 이미지에 빌드 도구를 포함하지 않았고, 비root 사용자로 실행한다. 로컬에 Gradle을 설치하지 않고 컨테이너 안에서 빌드해 재현성을 높였다.
- 확인한 것: 헬스체크 UP, 생성/조회 정상, 빈 제목 400, 없는 노트 404, 실행 사용자 appuser, 테스트 1개 통과.
- 배운 것: 이미지가 583MB로 큰 편이다. 개선 방법은 경량 베이스 이미지나 jlink.
- 비용: 로컬 작업만 했고 AWS 리소스는 만들지 않았다.
- 다음 할 일: ECR 저장소를 Terraform으로 만들고 이미지 푸시

## 2026-11-11
- 한 일: ECR 저장소를 Terraform으로 작성(`terraform/ecr.tf`). `apply`(23개 리소스) 후 Docker 이미지를 ECR에 푸시하고, AWS CLI로 이미지와 스캔 결과를 확인한 뒤 `destroy`로 삭제. 3단계 완료.
- 설계 포인트
  - 태그 불변(`IMMUTABLE`): 같은 태그로 다른 이미지를 덮어쓸 수 없어서 "배포된 버전"이 바뀌지 않는다.
  - 태그는 Git 커밋 해시(`5a06744`)를 사용했다. 이미지만 보고도 어떤 코드로 빌드했는지 추적할 수 있다.
  - 푸시할 때 취약점 스캔(`scan_on_push`), 이미지는 최근 10개만 유지(수명 주기 정책), 실습 후 정리를 위해 `force_delete` 적용.
- 확인한 것: ECR에 올라간 이미지는 약 164MB(압축 기준, 로컬 583MB는 압축을 푼 크기). 이미지 아키텍처는 `arm64`(Apple Silicon에서 빌드).
- 발견: 기본 스캔에서 HIGH 10, MEDIUM 4, LOW 4개가 나왔다. HIGH는 모두 베이스 이미지(`eclipse-temurin:21-jre`, Ubuntu)의 OS 패키지(perl, pcre2, apt)였고 앱 코드에서 나온 것은 없었다.
- 배운 것: 이미지 크기와 취약점은 대부분 베이스 이미지에서 온다. 경량 베이스로 바꾸면 두 문제를 함께 줄일 수 있다. ECS에서 실행할 때는 `arm64` 이미지에 맞춰 Fargate CPU 아키텍처를 `ARM64`로 지정해야 한다.
- 비용: ECR 저장 요금은 GB·월 단위라 몇 분 보관은 사실상 0. 작업 후 destroy로 정리하고 ECR, VPC, 보안 그룹 모두 0개임을 확인.
- 다음 할 일: 4단계 ECS Fargate + ALB 배포. 그 전에 베이스 이미지 경량화를 검토한다.

## 2026-11-11 (2)
- 한 일: 베이스 이미지 경량화와 취약점 조치. Ubuntu, Alpine, Distroless 세 가지 베이스를 같은 jar로 빌드해 크기, 동작, 취약점(Trivy)을 비교했고, Alpine으로 바꾼 뒤 Spring Boot를 4.1.0에서 4.1.2로 올렸다. 자세한 표는 `docs/03-app-docker.md`에 있다.
- 결과: 583MB에서 393MB로 줄었고, 취약점은 CRITICAL 7과 HIGH 8에서 MEDIUM 1로 줄었다. 테스트 1개 통과, 헬스체크 UP, 생성 201, 빈 제목 400, 없는 노트 404, 실행 사용자 appuser를 확인했다.
- 발견: CRITICAL 7개는 OS가 아니라 앱 라이브러리(Tomcat, Spring MVC, Jackson)에서 나왔다. 어제 ECR 기본 스캔은 OS 패키지만 검사해서 이 문제를 보여주지 않았다.
- 막힌 것: 처음에 Distroless가 셸과 패키지가 없으니 가장 안전할 거라고 짐작했다. 실제로 검사해 보니 Debian 패키지(libexpat1, libuuid1)에서 HIGH가 나와 Alpine보다 많았다. 짐작 대신 직접 측정해서 결정을 바꿨다.
- 배운 것: 이미지 취약점은 OS 계층과 애플리케이션 의존성 계층으로 나눠 봐야 한다. 크기는 베이스 이미지로 줄이고, 라이브러리 취약점은 프레임워크 버전으로 고친다. 프레임워크(Spring Boot)를 올리면 그 아래 라이브러리 버전이 한꺼번에 따라 올라간다.
- 비용: 로컬 작업만 했다. AWS 리소스는 만들지 않았다.
- 다음 할 일: 4단계 ECS Fargate + ALB 배포(A 방식: 프라이빗 서브넷 + NAT, 시간당 약 $0.12, 실습 후 destroy). Fargate CPU 아키텍처는 ARM64로 지정한다.

## 2026-11-12
- 한 일: NAT Gateway, ALB, ECS Fargate(클러스터, 작업 정의, 서비스), CloudWatch 로그 그룹, 실행 역할을 Terraform으로 작성. 37개 리소스로 배포해 ALB 주소에서 API를 호출하고, AWS CLI로 정리까지 확인. 4단계 완료. 자세한 내용은 `docs/04-ecs-alb.md`.
- 확인한 것: ALB 주소로 헬스체크 UP, 생성 201, 조회 200, 빈 제목 400, 없는 노트 404. 앱 작업은 프라이빗 서브넷에 있고 공인 IP가 없다.
- 막힌 것 1: 이미지 푸시가 `invalid reference format ... must be lowercase`로 실패했다. 처음에는 `terraform output`이 이상한 값을 준 줄 알고 AWS CLI로 주소를 받아 다시 해 봤지만 같은 에러가 났다. 주소를 바꿔도 같으니 원인은 주소가 아니었다. 실제 원인은 zsh에서 `$REPO:aa3e184`의 `:a`가 "절대 경로로 바꿔라"는 수식어로 해석된 것이었다. 어제는 태그가 `5`로 시작해 드러나지 않았다. `${REPO}:태그`처럼 중괄호로 감싸 해결했다.
- 막힌 것 2: 처음 1분 동안 대상 상태가 `unhealthy`였다. 로그를 보니 앱 기동이 67.5초 걸렸다(로컬 4초). 0.25 vCPU라 느리다. `health_check_grace_period_seconds = 120`을 미리 넣어 작업이 교체되지 않았다.
- 배운 것: ECS는 이미지가 ECR에 먼저 있어야 해서 첫 배포는 `-target`으로 ECR을 먼저 만든다. Fargate는 작업마다 IP를 받기 때문에 대상 그룹의 `target_type`이 `ip`여야 한다. 실행 역할은 ECS가 이미지를 받고 로그를 쓰는 권한이고, 앱 코드가 쓰는 권한(작업 역할)과는 다르다.
- 비용: 약 10분 사용, 1시간 단위 과금으로 약 $0.12. destroy 후 ALB, NAT, EIP, ECS, ECR, VPC, 로그 그룹, IAM 역할 0개 확인.
- 다음 할 일: 5단계 RDS(MySQL) 연결. 기동 시간 개선(0.5 vCPU 비교 또는 JVM 옵션)도 검토.

### 팀 프로젝트(project2)와 분리
- 한 일: 같은 맥에서 하는 팀 프로젝트와 겹치는 지점을 점검했다. 폴더, 저장소, 리전(시드니와 서울), 리소스 이름과 태그는 이미 달랐다. 겹치는 곳은 AWS 자격 증명(`~/.aws`의 `default` 프로필 하나)뿐이었다.
- 위험: 팀 계정 키로 `default`를 덮어쓰면 이 프로젝트의 `terraform apply`가 팀 계정에 리소스를 만들 수 있었다.
- 조치: provider에 `allowed_account_ids`를 추가했다. Public 레포라 계정 번호는 커밋되지 않는 `terraform.tfvars`에서 읽고, 형식만 `terraform.tfvars.example`로 남겼다. CLAUDE.md에 분리 규칙을 적었다.
- 확인한 것: 올바른 계정이면 plan이 정상이고, 다른 계정 번호를 주면 `AWS account ID not allowed`로 멈춘다. `terraform.tfvars`는 `git check-ignore`로 무시되는 것을 확인했다.
- 배운 것: 리소스 이름을 다르게 짓는 것만으로는 부족하다. 실수는 대부분 "어느 계정에 붙어 있는지 모르는 상태"에서 생긴다. 계정을 코드에서 고정하면 자격 증명이 바뀌어도 실행 단계에서 막힌다.

## 2026-11-13
- 한 일: 5단계 시작. Terraform state를 S3로 옮길 준비로 `bootstrap/`을 만들었다. S3 버킷(버전 관리, 암호화, 공개 차단, HTTPS 강제, 90일 정리, `prevent_destroy`)을 `apply`로 만들고 AWS CLI로 설정을 하나씩 확인했다. 이어서 `terraform/`에 `backend "s3"`를 연결했다(S3 네이티브 잠금). 자세한 내용은 `docs/05-remote-state.md`.
- 시작 점검: 지금 자격 증명이 개인 계정인지 확인하고, 태그로 범위를 좁혀 남은 리소스를 조회했다. ECS 클러스터와 작업 정의가 목록에 보였지만 둘 다 `INACTIVE`(삭제 후 기록만 남은 상태)였고 요금이 나가는 리소스는 0개였다.
- 막힌 것: 연결 후 `terraform state list | wc -l`이 5로 나와 리소스가 5개 있는 줄 알았다. 원문을 보니 "No state file was found!" 에러 문구의 줄 수였다(state가 비어 있음). `plan`의 "No value for required variable"은 `image_tag`가 필수 변수라서였다. 값을 넣으면 정상(37개 추가).
- 배운 것: 명령 출력을 `wc -l`로 세기 전에 원문을 먼저 본다. 에러 문구도 줄 수로 세어진다. 비어 있는 state는 S3에 파일이 만들어지지 않으므로, 실제 저장은 첫 apply에서 확인된다.
- 설계 포인트: 버킷 이름에 계정 번호 대신 무작위 접미사를 썼다. 잠금은 DynamoDB 대신 S3 네이티브 잠금(`use_lockfile`)이다. state 버킷은 destroy하지 않는 예외다.
- 비용: S3 버킷 1개(파일 몇 KB)로 사실상 0. 요금이 나가는 리소스는 만들지 않았다.
- 다음 할 일: 루트를 network / data / app으로 분리하고 `terraform_remote_state`로 연결.

## 2026-11-13 (2)
- 한 일: 루트를 `terraform/network`(무료)와 `terraform/app`(요금 발생)으로 분리. `git mv`로 파일 이력을 유지하며 옮기고, app이 network 값을 `terraform_remote_state`로 읽게 바꿨다. network는 `apply`(24개)해서 S3 저장을 확인했고, app은 `plan`(14개)까지 확인했다. 자세한 내용은 `docs/05-remote-state.md`.
- 설계 결정: NAT Gateway를 app으로 옮겨 network를 전부 무료로 만들었다. 프라이빗 라우팅 테이블은 network가 갖고, NAT로 나가는 경로(`aws_route`) 한 개만 app이 추가한다. app을 destroy하면 그 경로도 사라져 network가 항상 처음 상태로 돌아온다. 이 때문에 network의 라우팅 테이블에는 `route` 블록을 직접 쓰지 않는다(섞어 쓰면 서로 덮어쓴다).
- 확인한 것: 지난번 미확인이던 "S3에 장부가 실제로 저장되는지"를 확인했다. `network/terraform.tfstate`(약 42KB)가 올라갔고 버전 기록이 쌓였으며 로컬에는 state 파일이 생기지 않았다. 개수 검산: 옛 37개 → 분리 후 network 24 + app 14 = 38 (NAT 경로가 별도 리소스로 갈라진 1개 차이).
- 아직 안 한 것: app 루트의 실제 apply(NAT, ALB, ECS, 약 $0.12). `aws_route`가 network의 라우팅 테이블에 붙는지와 앱이 뜨는지는 이때 확인한다.
- 배운 것: 루트를 나누면 "누가 무엇을 소유하는가"를 정해야 한다. 라우팅 테이블처럼 두 루트가 같이 만지는 리소스는 소유자를 하나로 정하고 나머지는 별도 리소스로 얹는다. 비용 구조(켜 두면 요금이 나가는가)를 경계로 삼으면 나누는 이유가 분명해진다.
- 비용: network는 전부 무료이고 현재 켜져 있다(유지). 요금이 나가는 리소스는 만들지 않았다.
- 다음 할 일: app 루트 apply 검증과 destroy, 반복 패턴 모듈화.

## 2026-11-14
- 한 일: 5단계 마무리. network 코드를 `terraform/modules/network/`로 옮겨 모듈로 만들고, 루트를 나눈 뒤 처음으로 app 루트를 실제 배포해 확인하고 destroy했다. 5단계 완료. 자세한 내용은 `docs/05-remote-state.md`.
- 모듈 전환: `git mv`로 이력을 유지하며 옮기고, `moved` 블록 17개로 켜져 있던 리소스 24개의 장부 주소만 바꿨다. plan이 `24 moved, 0 add, 0 change, 0 destroy`였고, apply 전후 출력값 JSON이 같았다. 출력값 이름을 그대로 두어 app 루트는 고치지 않았다.
- 배포 확인: app apply(14개) 후 network 라우팅 테이블에 NAT 경로가 `active`로 붙었고, API가 정상이었다. app이 켜진 상태에서도 network plan이 `No changes`였다. destroy 후 라우팅 테이블은 원래대로 돌아왔다.
- 발견: 앱 기동 시간이 35.9초였다. 같은 설정(0.25 vCPU, 같은 이미지)인데 11/12의 67.5초와 차이가 크다. 두 번만 측정해서 원인은 아직 모른다. 8단계에서 기동 시간을 개선할 때 여러 번 재서 비교한다.
- 막힌 것: 옛 `terraform/` 폴더 정리 중 세션이 세 번 끊겼다. 명령을 하나씩 나눠 비교하니 읽기 명령, 일반 `rm`, `git rm`은 모두 정상이었고 `rm -rf`가 들어간 명령만 3번 모두 끊겼다. Claude 설정에는 이를 막는 규칙이 없어서, 사용 중인 도구가 위험 명령을 붙잡는 것으로 보인다(화면은 확인하지 못함). 남은 `terraform/.terraform` 폴더는 Git에서 무시되고 쓰지 않는 플러그인 캐시라 그대로 두었다.
- 배운 것: `moved` 블록은 "리소스는 그대로, 이름표만 바뀐다"를 Terraform에 알려 주는 장치다. 리팩터링 전에 plan에서 add/destroy가 0인지 먼저 확인하면 켜져 있는 인프라를 안전하게 옮길 수 있다. 여러 명령을 한 줄로 묶으면 문제가 생겼을 때 원인을 가리기 어렵다. 하나씩 나눠 실행하는 것도 변수를 하나씩 바꾸는 방법이다.
- 비용: app 약 10분(13:33 ~ 13:43), 1시간 단위 과금으로 약 $0.12. destroy 후 ALB, NAT, EIP, ECS 클러스터, ECR, 로그 그룹, IAM 역할 0개를 이 프로젝트 이름과 태그로 확인했다. network(무료)는 유지 중.
- 다음 할 일: 6단계 데이터 계층(RDS MySQL, Secrets Manager). 시작 전에 시드니 단가로 비용을 정리한다.
