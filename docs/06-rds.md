# 06. 데이터 계층 (RDS MySQL, Secrets Manager)

## 구조
```
terraform/network/  (무료, 유지)   DB 서브넷 db-a, db-b와 DB 보안 그룹은 2단계부터 있었다
terraform/data/     (요금 발생)    DB 서브넷 그룹, RDS MySQL. 암호는 RDS가 Secrets Manager에 직접 만든다
terraform/app/      (요금 발생)    작업 정의가 DB 주소(environment)와 암호(secrets)를 받는다
```
순서는 network -> data -> app이다. app은 `terraform_remote_state`로 data의 `db_host`, `db_name`, `db_secret_arn`을 읽는다.

## 설계 결정
| 결정 | 이유 |
|---|---|
| data를 app과 다른 루트로 | 앱을 다시 배포하거나 지워도 DB는 같은 계획에 들어가지 않는다 |
| `manage_master_user_password = true` | 암호를 RDS가 만들어 Secrets Manager에 넣는다. Terraform 코드와 state 파일에 암호가 남지 않는다 |
| 작업 정의 `secrets`로 주입 | 작업 정의에는 비밀의 위치(ARN)만 적는다. 값은 컨테이너가 시작할 때 ECS가 꺼낸다 |
| 실행 역할에 `GetSecretValue` 한 개 비밀만 허용 | 비밀을 꺼내는 주체는 앱이 아니라 ECS(실행 역할)다. 앱 코드는 AWS를 부르지 않아서 작업 역할은 아직 만들지 않았다 |
| 앱 `prod` 프로필 | 로컬과 테스트는 H2 그대로, AWS에서만 MySQL. 접속 정보는 환경 변수로만 받는다 |
| `db.t4g.micro`, gp3 20GB, 단일 AZ | 가장 작은 사양. 멀티 AZ는 요금이 2배라 8단계에서 켠다 |
| 삭제 방지, 최종 스냅샷, 백업 7일 | 실무 기본값. 실습 때는 삭제 방지를 끄는 apply 후 destroy하고, 최종 스냅샷은 지운다 |
| `publicly_accessible = false`, 저장 암호화 | DB는 앱 보안 그룹에서 오는 3306만 받는다 |

## 배포와 정리 절차
```bash
TAG=$(git rev-parse --short=7 HEAD)
(cd terraform/data && terraform apply)              # RDS 약 8분
cd terraform/app                                    # 이후는 docs/04-ecs-alb.md와 같다 (ECR -> 이미지 푸시 -> apply)

# 정리: 만든 순서의 반대
terraform destroy -var image_tag=$TAG               # app
cd ../data
terraform apply -var deletion_protection=false      # 삭제 방지 끄기 (그냥 destroy하면 AWS가 거부한다)
terraform destroy -var deletion_protection=false    # 최종 스냅샷을 남기고 삭제, 약 5분
aws rds delete-db-snapshot --db-snapshot-identifier aws-tf-springboot-mysql-final   # 보관 요금 방지
```

## 검증 결과 (2026-11-16)
- 로컬: Colima에 MySQL 8.4 컨테이너를 띄우고 `prod` 프로필로 접속. 노트 저장 -> 앱 재시작 -> 그대로 조회됨. 한글은 utf8mb4로 저장.
- 비밀: RDS가 만든 비밀에 `username`, `password` 두 칸이 있음을 값은 출력하지 않고 확인.
- RDS 설정: MySQL 8.4.11, 공개 접근 False, 저장 암호화 True, 삭제 방지 True, 백업 7일.
- 배포: 로그에 `profile is active: "prod"`, JDBC URL이 RDS 주소. 기동 39.6초.
- 영속성: 노트 저장 후 ECS 작업을 강제로 중지. 서비스가 새 작업을 띄운 뒤에도 노트가 그대로 조회됨.
- 삭제 방지: 켜진 상태에서 destroy하면 `Cannot delete protected DB Instance`로 거부됨.
- 정리 후 0개: app/data state, RDS 인스턴스, 수동 스냅샷, 자동 백업, RDS가 만든 비밀, ALB, NAT, EIP, ECS 작업, ECR, 로그 그룹. RDS가 만든 비밀은 DB와 함께 삭제된다.

## 알려진 한계
- RDS가 관리하는 암호는 7일마다 자동 교체된다. 앱은 시작할 때만 암호를 받으므로, 오래 켜 두면 교체 후 작업을 재시작해야 한다.
- 스키마는 `ddl-auto: update`로 만든다. 스키마 변경 이력이 필요해지면 Flyway로 바꾼다.
