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

## 2026-11-16
- 한 일: 6단계 데이터 계층. 앱에 MySQL 드라이버와 `prod` 프로필을 추가하고, `terraform/data/` 루트(RDS MySQL)를 새로 만들었다. 암호는 RDS가 Secrets Manager에 직접 만들고, ECS 작업 정의의 `secrets`로 컨테이너에 넣었다. 로컬 MySQL 컨테이너로 먼저 확인한 뒤 AWS에 배포해 확인하고 모두 지웠다. 6단계 완료. 자세한 내용은 `docs/06-rds.md`.
- 확인한 것: 노트를 저장하고 ECS 작업을 강제로 중지했다. 새 작업이 뜬 뒤에도 노트가 남아 있었다(H2였다면 사라진다). 삭제 방지가 켜진 상태의 destroy는 AWS가 거부했다.
- 계획과 달라진 것: 작업 역할을 만들 계획이었는데 필요 없었다. 비밀을 꺼내는 건 앱이 아니라 ECS이므로 실행 역할에 비밀 하나만 읽는 권한을 더했다. 앱이 S3 같은 AWS 서비스를 직접 부를 때 작업 역할을 만든다.
- 막힌 것: MySQL 콘솔에서 한글이 `??`로 보였다. API 응답과 테이블 문자셋(utf8mb4)은 정상이었고, 콘솔 접속에 `--default-character-set=utf8mb4`를 주니 제대로 보였다. 저장 문제가 아니라 조회 도구의 표시 문제였다. 또 작업 교체를 기다리는 스크립트가 끝나지 않았는데, 대상 그룹 이름을 잘못 적은 탓이었다(`aws-tf-springboot-tg`). 이름을 짐작하지 말고 조회해서 쓴다.
- 배운 것: 실행 역할(ECS가 컨테이너를 띄울 때 쓰는 권한)과 작업 역할(앱 코드가 쓰는 권한)의 경계가 비밀 주입에서 분명해졌다. `manage_master_user_password`를 쓰면 암호가 state에도 남지 않는다. 삭제 방지는 destroy를 두 단계로 만들지만 실수로 DB를 지우는 사고를 막는다.
- 기동 시간: 39.6초 (11/12 67.5초, 11/14 35.9초). 측정을 계속 모은다.
- 비용: RDS 약 37분(09:39 ~ 10:16), app 약 19분(09:49 ~ 10:08). 예상 약 $0.15. 정리 후 RDS 인스턴스, 스냅샷, 자동 백업, 비밀, ALB, NAT, EIP, ECS 작업, ECR, 로그 그룹 0개를 확인했다. network(무료)는 유지.
- 다음 할 일: 7단계 GitHub Actions CI/CD (OIDC).

## 2026-11-17
- 한 일: 7단계 GitHub Actions. CI(PR과 main: 앱 테스트, ARM 이미지 빌드, Terraform fmt/validate)를 만들고 GitHub에서 3개 모두 통과를 확인했다. ECR을 `terraform/registry` 루트로 옮겨 항상 켜 두고, main에 들어온 커밋은 ECR에 푸시하고 app이 켜져 있으면 ECS까지 배포하는 CD를 붙였다. 자세한 내용은 `docs/07-cicd.md`.
- 막힌 것: OIDC 공급자를 조회하자 `explicit deny in a service control policy`가 났다. 생성도 한 번 시도했는데 같은 이유로 거부됐다. 처음에는 다른 사람이 관리하는 조직이라고 짐작했는데, `describe-organization`으로 확인하니 관리 계정이 내 Gmail로 등록돼 있었다. 하지만 그 이메일로 루트 로그인이 되지 않아(`An AWS account with that sign-in information does not exist`) SCP를 고칠 수 없었다.
- 결정: OIDC 대신 배포 전용 IAM 사용자의 장기 키를 GitHub 비밀값에 넣었다. 권한은 이 ECR 저장소 1개 푸시, 이 ECS 서비스 1개 갱신, 실행 역할을 ECS에만 넘기기로 좁혔다. 키는 state에 남지 않게 Terraform 밖에서 만들었다. 관리자 키는 쓰지 않았다.
- 확인한 것: CD 첫 실행에서 ECR 푸시 성공, app이 꺼져 있어 배포는 건너뜀. Public 저장소라 로그가 공개되는데 계정 번호 노출 0회.
- 배운 것: 보안 설계는 이상적인 방법(OIDC)이 막혔을 때 "무엇을 포기하고 위험을 어떻게 줄였는지"를 설명할 수 있어야 한다. SCP는 멤버 계정의 관리자 권한보다 위에 있어서, IAM 권한이 있어도 막힌다. 또 짐작으로 결론 내리지 말고 조회해서 확인한다(조직의 주인을 잘못 짐작했다).
- 비용: 요금이 나가는 리소스는 만들지 않았다. ECR 이미지(127MB, 월 약 1센트)는 작업을 마치며 지웠다. 켜 둔 것은 network, registry(빈 ECR, IAM 사용자), state 버킷으로 모두 무료.
- 다음 할 일: app을 켠 상태에서 CD 자동 배포 검증. 관리 계정 로그인은 AWS 지원(계정 문의는 무료)에 따로 문의해 볼 수 있다.

## 2026-11-18
- 한 일: 7단계 마무리. app이 켜진 상태에서 main에 푸시하면 CD가 ECS를 새 이미지로 바꾸는지 확인했다. 확인용으로 `/actuator/info`에 빌드 버전을 표시하게 하고(`buildInfo()`), 버전을 0.0.2로 올려 푸시했다. 7단계 완료. 자세한 내용은 `docs/07-cicd.md`.
- 확인한 것: CD 4개 작업 모두 성공, 서비스 이미지 태그가 `599a8e3`으로 바뀌고 버전이 0.0.1 -> 0.0.2. 배포 중 1초마다 보낸 요청 186번이 모두 200이라 중단이 없었다. 몇 초 동안 두 버전이 번갈아 응답했는데 롤링 배포에서 옛 작업과 새 작업이 잠깐 같이 떠 있기 때문이다.
- 시간 절약: CD가 첫 이미지를 빌드하는 동안 RDS apply를 동시에 돌렸다(RDS 7분 49초).
- 막힌 것: 정리 때 ECR 이미지 2개를 지우는 명령이 0개를 지웠다. 이미지 ID들을 변수 하나에 담아 넘겼는데, zsh는 bash와 달리 변수를 공백으로 나누지 않아 두 값이 한 덩어리로 전달됐다. 태그를 직접 나열해 지웠다.
- 발견: app을 destroy해도 CD가 등록한 작업 정의 버전(5)은 Terraform이 몰라서 남았다. 요금은 없지만 정리 절차에 deregister를 추가했다. "Terraform 밖에서 만든 것은 Terraform이 지우지 않는다"는 것을 확인했다.
- 배운 것: 무중단 배포를 말로만 하지 않고 배포 중 요청을 보내 숫자(186/186)로 확인하면 설명할 때 근거가 된다.
- 비용: RDS 약 32분(09:25 ~ 09:57), app 약 16분(09:33 ~ 09:50). 예상 약 $0.15. 정리 후 RDS, 스냅샷, 자동 백업, 비밀, ALB, NAT, EIP, ECS 작업, 활성 작업 정의, ECR 이미지, 로그 그룹 0개 확인.
- 다음 할 일: 8단계 고가용성과 관측(멀티 AZ, 자동 확장, CloudWatch 경보, 기동 시간 개선).

## 2026-11-19
- 한 일: ECS 작업 2개를 두 AZ에 분산하고, 평균 CPU 60%를 목표로 2~4개에서 자동 조절하게 했다. ALB 5xx, 앱 p95 응답 시간, RDS CPU 경보를 추가했다. 기동 시간 비교용으로 Fargate 작업당 0.25 또는 0.5 vCPU를 지정할 수 있게 했다. [8단계 구성과 검증 순서](08-ha-observability.md).
- 확인한 것: 실제 AWS `data` 계획은 RDS 인스턴스, 서브넷 그룹, CPU 경보 3개 추가를 예상했다. `app` 계획은 이전 실습을 정리한 뒤 비어 있는 RDS 출력이 필요했다. 임시 값으로 두 Fargate 사양의 앱 계획을 실행해 배치, 자동 확장, 경보 구성을 확인했다.
- 배운 것: Terraform이 서비스의 초기 작업 수를 정하고, 실행 중에는 Application Auto Scaling이 작업 수를 관리한다. ECS를 두 AZ에 분산해도 NAT와 RDS가 단일 AZ이면 해당 AZ의 장애는 여전히 영향을 줄 수 있다.
- 준비: 읽기 전용 계획과 모의 검증을 먼저 실행하고, 비용 승인 후 실제 AWS 실습을 시작했다.
- 실습: `b73a13a`를 GitHub에 푸시했고 CI/CD가 성공했다. 시드니에서 `data` 3개, `app` 17개를 배포했다. ECS 작업이 AZ마다 하나씩 배치됐고, 한 작업을 중지하는 동안 헬스체크 130건이 모두 200이었다. 교체 작업은 2분 49초 뒤 정상으로 전환됐다. ALB 5xx 경보가 실제로 `ALARM`으로 바뀌었다.
- 막힌 것: DB 조회 부하에서는 연결 풀 타임아웃과 ECS 작업 교체가 발생했다. RDS가 자체 복구를 기록했고, 실습 DB 재부팅 뒤 0.5 vCPU 작업 두 개가 정상화됐다. 0.25 vCPU 초기 기동은 39.0~79.0초, 0.5 vCPU는 35.6~37.3초였다. 각 작업의 메모리와 DB 상태도 달라 CPU만의 효과를 분리하지 못했다.
- 배운 것: ECS가 `RUNNING`인 동안에도 ALB `healthy` 전환까지 기다려야 한다. DB 연결을 기다리는 요청이 많아도 ECS CPU는 자동 확장 조건을 충족하지 않을 수 있다. DB를 조회하지 않는 경로는 380,443건이 모두 200이었지만, 조회한 분당 평균 CPU는 최고 45.9%라 작업이 2개로 유지됐다.
- 정리: 적용 시작부터 삭제 완료까지 app 약 40분, data 약 55분. AWS CLI로 실습 리소스와 ECR 이미지 0개를 확인했고, app/data state도 비었다. network 계획은 변경 없음.
- 다음 할 일: DB 조회 부하와 ECS CPU 부하를 구분해 실제 자동 확장과 축소를 재검증한다. 자세한 결과는 [8단계 실습 기록](08-ha-observability.md)에 남겼다.
- 재검증: 시드니에서 조직 SCP가 RDS, ALB, NAT Gateway 생성을 명시적으로 거부했다. DB 없는 H2 구성도 ALB와 NAT를 만들 수 없어 ECS 확장·축소는 미검증 상태다. 부분 생성 8개와 ECR 이미지 1개를 정리하고 실습 리소스 0개를 확인했다.

## 2026-11-20

- CloudTrail에서 시드니의 RDS, ALB, NAT 생성 요청 3건에 명시적 거부가 기록된 것을 확인했다. 현재 계정의 `organizations:DescribePolicy` 호출도 거부돼 정책 내용을 확인할 수 없었다.
- AWS 접근 없이 ECS 자동 확장 구성을 검증하는 Terraform 테스트를 추가했다. 실제 확장·축소 실측은 정책 제한을 확인한 뒤 이어간다.

## 2026-11-24
- 한 일: 11/19부터 RDS, ALB, NAT 생성을 막던 SCP의 원인을 찾았다. 결론은 관리 계정 문제가 아니라 **지출 한도(spend limit)** 때문이었다.
- 조사 과정: 처음에는 관리 계정에 루트로 로그인해야 SCP를 고칠 수 있다고 보고 AWS 지원팀에 문의했다. settings.aws.com을 열어 보니 이 계정은 Google 로그인으로 "프로젝트"를 관리하는 새 가입 방식이었고, 고급 기능을 켜기 전에는 루트 비밀번호가 없다. 그래서 루트 로그인이 `Bad request`로 실패했다. 고급 기능을 켜면 SCP를 고칠 수 있지만 되돌릴 수 없고 지출 한도도 사라진다. 결정하기 전에 공식 문서를 읽었고, 지출 한도 문서의 SCP(DenyCompute, DenyDatabase)가 막는 작업이 거부된 세 작업과 같았다.
- 확인한 것: 메일함에서 AWS 지출 한도 알림을 찾았다. 한도 $20인데 실습한 날 하루치 요금으로 계산한 월 예상 요금이 $37.10이 되자 AWS가 새 리소스 생성을 자동으로 막았다. 시각을 맞춰 보면 차단(11/19 11:10) -> CloudTrail 거부 기록(13:48, 13:51) -> 해제(14:39) 순서다. 지금은 `ec2 run-instances --dry-run`이 성공하고(실제 생성 없이 권한만 검사), 11/17에 거부됐던 OIDC 공급자 조회도 된다.
- 결정: 고급 기능은 켜지 않는다. 필요 없고, 되돌릴 수 없으며, 비용 안전장치인 지출 한도가 없어진다. 지원팀 문의는 더 진행할 필요가 없다.
- 배운 것: 증상(SCP 거부)만 보고 "관리 계정에 들어가야 한다"고 짐작해 며칠을 썼다. 거부된 작업 목록을 공식 문서의 정책과 맞춰 보고, 알림 메일의 시각을 CloudTrail 기록과 맞춰 보니 원인이 바로 확인됐다. 지출 한도는 현재 금액이 아니라 예상 금액으로 막기 때문에, 짧고 비싼 실습을 하면 실제 요금이 $1 미만이어도 걸릴 수 있다.
- 확인한 것(비용): 시드니에서 NAT, ALB, RDS와 수동 스냅샷, ECS 클러스터, 활성 작업 정의, ECR 이미지, 연결 안 된 EIP 모두 0개. 이번 달 요금 $0.83.
- 조치: 지출 한도를 $20에서 $40로 올렸다(settings.aws.com, 사용자가 직접 변경). 상태 `Within limit`, 이번 달 $0.83은 Free Tier 크레딧으로 처리될 예정이다. 한도는 요금이 아니라 "잊었을 때 최대 손해"를 정하는 상한선이라, 정리 절차는 그대로 지킨다.
- 8단계 실측: 한도를 올린 뒤 같은 날 바로 실습했다. CPU 부하로 작업 수가 2 -> 4로 늘고(CPU 상승 후 약 5분 30초), 부하를 끄자 4 -> 3 -> 2로 하나씩 줄어드는 것(부하 종료 후 약 16분)을 확인했다. 부하 435,969건 중 실패 0건. 8단계의 남은 항목을 마쳤다. [실측 결과](08-ha-observability.md)
- 막힌 것: `ab`를 오래 돌리면 멈췄다. 연결 재사용 옵션만 바꿔 비교해 보니 옵션 문제는 아니었고, 30초씩 반복 실행해 피했다. 멈춘 원인은 아직 모른다.
- 배운 것: 자동 확장은 빠르게 늘리고 천천히 줄인다(확장 3분 기준 한 번에, 축소 15분 기준 하나씩). 서비스가 흔들리지 않게 하려는 비대칭이다. 실제 반응 시간에는 지표 지연(1~2분)도 더해진다.
- 비용: app 약 44분, data 약 59분, 예상 약 $0.2(크레딧 차감). 최종 스냅샷과 ECR 이미지까지 지우고 요금 리소스 0개 확인. network 계획 변경 없음.
- 다음 할 일: OIDC 공급자 생성이 가능한지 확인하고, 되면 장기 키 대신 OIDC로 바꾼다. push 여부를 정한다.

## 2026-11-25
- 한 일: GitHub Actions의 AWS 접근을 장기 키에서 OIDC 역할로 바꿨다. GitHub 저장소에 남은 비밀값은 역할 ARN 하나이고, 키는 없다. 자세한 내용은 `docs/07-cicd.md`.
- 원인 확인: 11/17에 OIDC를 막은 정책은 지출 한도 SCP가 아니라 다른 관리형 SCP였다(CloudTrail의 정책 ID가 달랐다). 11/24부터는 같은 조회가 허용됐다. 바뀐 이유는 확인하지 못했다.
- 진행 순서: 옛 사용자와 새 역할이 같은 권한 정의(`locals`)를 쓰게 하고, CI를 역할로 바꿔 성공을 확인한 뒤에 사용자와 키를 지웠다. 확인 전에 키를 지우면 CD가 끊긴다.
- 막힌 것: 첫 실행이 `Not authorized to perform sts:AssumeRoleWithWebIdentity`로 실패했다. CloudTrail의 실패 기록에서 토큰의 실제 `sub`를 보니 `repo:소유자@ID/레포@ID:ref:refs/heads/main` 형식이었다. 조건을 이 형식으로 고치자 성공했다. ID까지 비교하면 같은 이름으로 다시 만든 레포도 막을 수 있다.
- 확인한 것: CI 로그의 역할 ID가 새 역할과 같았고, 옛 키의 마지막 사용은 전날이었다. 키, IAM 사용자, GitHub 비밀값 2개를 지웠다. CI가 올린 이미지도 지웠다.
- 배운 것: 인증이 거부되면 내가 쓴 조건을 다시 읽기보다 상대가 실제로 보낸 값을 먼저 본다. CloudTrail 실패 기록에 그 값이 남는다.
- 비용: 모두 무료 리소스(OIDC 공급자, IAM 역할). 요금 리소스는 만들지 않았다.
- 오후: 8단계를 완료로 표시하고 README를 OIDC 기준으로 고쳤다. 9단계 EKS의 코드를 준비했다(apply는 다음에).
  - `terraform/eks/`: 클러스터(1.37, Access Entry), 관리형 노드 그룹(t4g.medium 2대, ARM), 애드온 5개(VPC CNI, kube-proxy, CoreDNS, Pod Identity Agent, metrics-server), NAT, ALB Controller 권한(Pod Identity), RDS 접속 허용 규칙. plan 결과 22개.
  - `k8s/`: Kustomize base(Deployment, Service, Ingress, HPA)와 prod overlay. `deploy.sh`(ALB Controller 설치, DB Secret, 배포), `teardown.sh`(Ingress를 먼저 지우고 ALB가 0개가 될 때까지 기다림).
  - 확인한 것: 계정 플랜 정책이 `eks:*`를 허용하고 스팟은 거부한다(온디맨드로 설정). 1.37이 표준 지원(2027-12까지)이라 연장 지원 요금이 붙지 않는다. ALB Controller는 하루 전 나온 v3.7.0 대신 v3.6.3을 정책과 차트에 같이 고정했다.
  - 설계 메모: EKS가 만든 ALB는 Terraform이 모른다. 클러스터를 먼저 지우면 ALB가 남아 요금이 계속 나가므로 teardown을 먼저 한다. ECR 주소에 계정 번호가 있어 매니페스트에는 `image: app`만 두고 배포 때 바꾼다. EBS CSI는 지금 앱이 볼륨을 쓰지 않아 뺐다.

## 2026-11-26
- 9단계 EKS 사전 점검: 시드니 개인 계정에서 EKS는 22개, RDS는 3개 생성 계획을 확인했다. 기존 리소스의 변경·삭제 계획은 없었다. EKS 1.37은 표준 지원이며 애드온 5개 모두 ARM64 기본 버전이 있다.
- `terraform fmt`·`validate`, Kustomize 매니페스트 생성, 배포·정리 스크립트 문법 검사를 통과했다. 로컬 ARM64 이미지에서 헬스 체크와 노트 생성·조회·삭제도 확인했다. 로컬 기본 프로필은 H2를 쓰므로 EKS와 RDS 연결 검증은 배포 후 한다.
- 시드니 온디맨드 요금 기준으로 클러스터, 노드 2대, NAT, ALB, 공인 IPv4 3개, RDS와 스토리지에 시간당 약 $0.32가 든다. 데이터 처리와 시간 단위 과금을 감안해 2시간 실습은 세금·크레딧 전 $0.70~$1.00로 추산했다. [AWS EKS 요금](https://aws.amazon.com/eks/pricing/), [시드니 EC2 요금표](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/ap-southeast-2/index.json), [시드니 ALB 요금표](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSELB/current/ap-southeast-2/index.json), [시드니 RDS 요금표](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonRDS/current/ap-southeast-2/index.json), [AWS VPC 요금](https://aws.amazon.com/vpc/pricing/)
- 배포 전 확인 결과: EKS, ECS, NAT, ALB, RDS, 프로젝트 공인 IP, RDS 수동 스냅샷, ECR 이미지 모두 0개다.
- 9단계 EKS 전환을 완료했다. 시드니에서 ARM64 노드를 두 가용 영역에 한 대씩 띄웠고 앱 파드 2개와 ALB 대상 2개가 모두 정상 상태가 됐다. ALB를 통해 RDS 노트 생성·조회·삭제를 검증했고 HPA의 CPU 지표를 확인했다. [EKS와 ECS 비교 및 실측 결과](09-eks.md)
- 새 ALB 주소를 맥의 기본 DNS 조회에서 바로 찾지 못했다. `dig`에서 받은 IPv4를 `curl --resolve`에 전달해 같은 ALB에 연결했다.
- Terraform 적용 시작부터 정리 완료까지 24분 12초 걸렸다. ALB를 먼저 지운 뒤 EKS와 RDS를 정리했다. AWS CLI로 노드·디스크, NAT·공인 IP, RDS·스냅샷·자동 백업·관리 비밀, ALB·대상 그룹, 실습용 ECR 이미지가 모두 0개임을 확인했다. 두 Terraform state도 비었다.

## 2026-11-27
- 한 일: 10단계 GitOps와 모니터링을 준비하고 같은 날 시드니 EKS에서 검증했다. [자세한 결과](10-gitops-monitoring.md)
  - 매니페스트를 별도 Public 레포 `aws-tf-springboot-manifests`로 옮겼다. CI는 이미지를 올린 뒤 그 레포의 태그만 커밋하고(레포 하나에만 쓰는 배포 키), Argo CD가 배포한다.
  - 앱에 Prometheus 지표를 추가했다. EKS에서는 관리 포트를 8081로 옮겨 지표가 ALB로 나가지 않게 했다(ALB로 404 확인).
  - kube-prometheus-stack과 골든 시그널 경보 4개. Slack 웹훅은 SSM SecureString에 두고 Alertmanager가 파일로 읽는다. Slack은 팀 워크스페이스와 섞지 않으려고 개인 워크스페이스를 새로 만들었다.
- 확인한 것: 부하로 HPA 2 -> 4, 3분 뒤 경보가 Slack에 왔고 해제 알림도 왔다. main 푸시부터 Argo CD 배포 완료까지 3분 16초, 매니페스트 `git revert`로 되돌리기 3분 40초.
- 막힌 것과 해결:
  - Argo CD가 이미지 이름(ECR 주소)을 덮어쓰면 같은 층의 태그가 지워졌다. 실습 전에 로컬 kustomize로 재현해서 알았고, 태그를 한 층 아래(base)로 옮겼다.
  - `newTag: 0000000`을 YAML이 숫자로 읽어 kustomize가 거부했다. 태그에 따옴표를 붙였다.
  - SSM 파라미터 이름 `/aws-tf-springboot/...`가 `reserved parameter name`으로 거부됐다. 이름은 `aws`, `ssm`으로 시작할 수 없다.
  - Maven Central이 CI에 429(요청 과다)를 돌려줘 테스트가 실패했다. 같은 실행의 이미지 빌드는 성공해서 일시적인 문제로 보고 재실행했다.
  - 축소 중 51건, 배포 중 40건이 실패했다. 앱 지표에 5xx가 없어 ALB가 내려가는 파드로 보낸 요청으로 판단했다. `preStop` 15초 하나만 넣고 같은 조건에서 다시 재자 축소와 배포 모두 0건이었다.
  - `deploy.sh`가 Argo CD 첫 동기화 전에 끝났다. Application의 `Healthy`가 리소스 생성 전에도 잠깐 뜬다. 실제 결과(Deployment, 롤아웃, Ingress 주소)를 기다리게 고쳤다.
- 배운 것: 오류가 0인 상태를 만들려면 "새 파드가 준비될 때"뿐 아니라 "옛 파드가 빠질 때"도 설계해야 한다. 로드 밸런서가 대상을 빼는 시간과 파드가 내려가는 시간이 어긋나면 실패가 난다. 그리고 도구의 "완료" 표시보다 내가 원하는 결과를 직접 기다리는 쪽이 정확하다.
- 계획: 로드맵에 11단계 RDS PITR 데이터 복구 실습을 추가했다(12월 19일 이후 진행).

## 2026-11-28

- 시험 기간 작업 1번을 완료했다. 월 지출 한도 $40, 1~10단계 완료 상태, 11월 27일 AWS 정리 결과를 로드맵에 반영했다. [로드맵 현재 상태](roadmap.md#현재-상태-2026-11-28)
- 지출 한도 변경 근거는 11월 24일 개발 일지에, 실습 리소스 삭제 확인은 11월 27일 GitOps 실측 문서에 연결했다.
- 같은 날 작업 2번도 완료했다. ECS와 EKS의 삭제 순서, RDS 최종 스냅샷과 ECR 이미지 삭제, EKS ENI와 보안 그룹 점검을 한 문서에 모았다. 시드니 개인 계정에서 조회 명령 14개가 모두 0이었고 ENI와 보안 그룹 목록도 비어 있었다. [리소스 정리 절차](teardown.md)
- 다음 작업은 ECS 아키텍처 그림이다. RDS 특정 시점 복원 실습은 12월 19일 시험 이후에 진행한다.
