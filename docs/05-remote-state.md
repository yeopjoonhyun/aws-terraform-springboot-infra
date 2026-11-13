# 05. Terraform 원격 state (S3)

## 왜 옮기나
Terraform은 "무엇을 만들었는지"를 state 파일에 기록한다. 지금까지는 내 컴퓨터에 있었다. 그러면 파일을 잃으면 AWS에 있는 리소스를 Terraform이 알아보지 못하고, CI/CD(GitHub Actions)에서는 같은 state를 볼 수 없다. S3로 옮기면 버전 관리, 암호화, 잠금을 얻고 어디서든 같은 기록을 쓴다.

## 구조 (루트 분리, 2026-11-13)
```
bootstrap/          state 보관용 S3 버킷을 만든다. 이 폴더의 state만 로컬에 둔다.
terraform/network/  VPC, 서브넷 6개, 인터넷 게이트웨이, 라우팅 테이블, 보안 그룹 3개. 전부 무료. (key: network/terraform.tfstate)
terraform/app/      ECR, NAT Gateway, ALB, ECS, 로그, 실행 역할. 시간당 요금 발생.  (key: app/terraform.tfstate)
```
`terraform/app`은 `terraform_remote_state`로 network의 출력값(VPC ID, 서브넷 ID, 보안 그룹 ID)을 읽는다. 순서는 항상 network 다음 app이다.

### 왜 나눴나
- **변경의 영향 범위**: 앱을 다시 배포해도 네트워크는 건드리지 않는다. 한 장부에 다 묶여 있으면 앱 변경 때 네트워크까지 같은 계획에 포함된다.
- **비용 구조에 맞춘 분리**: 요금이 나가는 NAT를 app으로 옮겨서 network를 **전부 무료**로 만들었다. 그래서 network는 켜 둬도 되고, app만 쓰고 나서 지운다.
- **CI/CD 준비**: 파이프라인이 app만 배포하고 network는 읽기만 하도록 권한을 나눌 수 있다.

### 두 루트가 만나는 지점
프라이빗 서브넷의 라우팅 테이블은 network가 갖고, 그 위에 "밖으로 나가는 길(NAT)" `aws_route` 하나만 app이 추가한다. app을 destroy하면 이 길도 사라져서 network는 항상 처음 상태로 돌아온다. 이 때문에 network의 라우팅 테이블에는 `route` 블록을 직접 쓰지 않는다(app의 `aws_route`와 충돌한다).
버킷을 만드는 코드는 버킷이 생기기 전에 state를 둘 곳이 없어서 따로 분리했다(닭과 달걀 문제).

## 버킷 설정
| 설정 | 이유 |
|---|---|
| 버전 관리 | state가 잘못 덮어써져도 이전 버전으로 되돌릴 수 있다 |
| 암호화(AES256) | state에는 민감한 값이 들어갈 수 있다 |
| 외부 공개 차단 4종 | 실수로 공개되는 것을 막는다 |
| HTTPS가 아니면 거부 | 전송 구간 보호 |
| 옛 버전 90일 후 삭제 | 저장 비용이 쌓이지 않게 한다 |
| `prevent_destroy` | 실수로 destroy해도 state 버킷이 지워지지 않는다 |
| `use_lockfile` | 동시에 두 곳에서 apply하지 못하게 S3에 잠금 파일을 둔다 (DynamoDB 불필요, Terraform 1.10 이상) |

## 설계 결정
- 버킷 이름에는 계정 번호 대신 무작위 접미사를 썼다. 레포가 Public이라 계정 정보가 드러나면 안 된다.
- 잠금은 DynamoDB 테이블 대신 S3 네이티브 잠금을 썼다. 관리할 리소스가 하나 줄어든다.
- 이 버킷은 실습 후 destroy 대상이 아니다. state가 들어 있기 때문이다. 비용은 파일 몇 KB라 사실상 0이다.

## 검증한 것
- `terraform apply`로 7개 리소스 생성 후 AWS CLI로 확인: 버전 관리 Enabled, 암호화 AES256, 공개 차단 4종 True, HTTPS 강제 정책, 옛 버전 90일 정리.
- backend를 연결하고 `terraform init`이 `Successfully configured the backend "s3"`로 끝났다.
- **network 루트 apply(24개 리소스) 후 S3에 `network/terraform.tfstate`(약 42KB)가 실제로 저장됐다.** 버전 기록이 쌓였고, 로컬에는 state 파일이 생기지 않았다.
- app 루트의 `terraform plan`이 network의 출력값을 원격 state로 읽어 와서 14개 추가로 정상 계산됐다.
- 개수 검산: 옛 단일 루트는 37개, 분리 후 network 24 + app 14 = 38개다. 1개 차이는 프라이빗 라우팅 테이블 안에 들어 있던 NAT 경로가 별도 리소스(`aws_route`)로 갈라졌기 때문이다.

## 아직 확인하지 못한 것
- **app 루트를 실제로 apply해서 `aws_route`가 network의 라우팅 테이블에 붙고 앱이 뜨는 것**은 아직 확인하지 않았다. 요금이 나가는 단계(약 $0.12)라서 확인 후 진행한다.
- 잠금 파일은 apply 도중에만 존재해서 따로 확인하지 못했다.

## 사용법
```bash
cd bootstrap && terraform apply         # 버킷 생성 (최초 1회)
cd terraform/network && terraform init && terraform apply     # 네트워크 (무료, 유지)
cd terraform/app && terraform init                            # 앱 (요금 발생)
cd terraform/app && terraform plan -var image_tag=<커밋 해시>
```
세 폴더(`bootstrap`, `terraform/network`, `terraform/app`) 각각의 `terraform.tfvars`에 `aws_account_id`가 필요하다(커밋되지 않음, 형식은 폴더별 `terraform.tfvars.example`).

## 다음 단계
- app 루트를 한 번 apply해서 분리가 실제로 동작하는지 검증하고 destroy
- 6단계에서 data 루트(RDS)를 추가하고 같은 방식으로 연결
- 반복되는 패턴은 모듈로
