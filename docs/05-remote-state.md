# 05. Terraform 원격 state (S3)

## 왜 옮기나
Terraform은 "무엇을 만들었는지"를 state 파일에 기록한다. 지금까지는 내 컴퓨터에 있었다. 그러면 파일을 잃으면 AWS에 있는 리소스를 Terraform이 알아보지 못하고, CI/CD(GitHub Actions)에서는 같은 state를 볼 수 없다. S3로 옮기면 버전 관리, 암호화, 잠금을 얻고 어디서든 같은 기록을 쓴다.

## 구조
```
bootstrap/   state 보관용 S3 버킷을 만든다. 이 폴더의 state만 로컬에 둔다.
terraform/   실제 인프라. backend "s3"로 위 버킷에 state를 저장한다 (key: app/terraform.tfstate).
```
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
- `terraform/`에 backend를 연결하고 `terraform init -migrate-state`가 `Successfully configured the backend "s3"`로 끝났다.
- backend 연결 후 `terraform plan -var image_tag=...`가 정상 동작한다 (37개 추가, 비어 있는 state와 일치).

## 아직 확인하지 못한 것
- 비어 있는 state는 S3에 파일이 만들어지지 않는다. 그래서 **실제로 S3에 state가 쓰이고 잠금 파일이 생기는지는 첫 apply 때 확인한다.**

## 사용법
```bash
cd bootstrap && terraform apply         # 버킷 생성 (최초 1회)
cd terraform && terraform init          # backend 연결
cd terraform && terraform plan -var image_tag=<커밋 해시>
```
`bootstrap/terraform.tfvars`와 `terraform/terraform.tfvars`에 `aws_account_id`가 필요하다(커밋되지 않음, 형식은 `terraform.tfvars.example`).

## 다음 단계
- 루트 분리: network / data / app을 별도 폴더와 별도 state로 나누고 `terraform_remote_state`로 연결
- 반복되는 패턴은 모듈로
