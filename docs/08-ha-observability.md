# 8단계 고가용성과 관측

## 구성

- ECS Fargate는 두 가용 영역(AZ)의 프라이빗 앱 서브넷을 사용한다. 작업 2개로 시작하고, 한쪽에 작업이 몰리면 ECS가 두 AZ에 재분배한다.
- Application Auto Scaling은 ECS 서비스의 평균 CPU 사용률 60%를 목표로 작업 수를 2~4개로 조절한다. 확장 후 120초, 축소 후 180초의 대기 시간을 설정했다. Terraform은 처음 작업 수를 지정하고 이후에는 자동 확장이 조절한 값을 덮어쓰지 않는다.
- Fargate 기본값은 0.25 vCPU와 512 MiB다. `task_vcpu=0.5`로 설정하면 0.5 vCPU와 1 GiB가 된다. 두 Fargate 사양에서 기동 시간을 비교할 수 있다.
- NAT Gateway와 RDS는 각각 한 AZ에 있다. 작업 하나가 사라지는 상황을 검증하며, NAT 또는 RDS가 있는 AZ 전체에 장애가 나면 앱에 영향이 갈 수 있다.

## CloudWatch 경보

| 경보 | 조건 |
| --- | --- |
| `${project_name}-alb-5xx` | ALB가 생성한 5xx가 최근 3분 중 2분 이상 분당 5건 이상 |
| `${project_name}-target-latency` | 앱 응답 시간 p95가 최근 3분 중 2분 이상 1초 초과 |
| `${project_name}-rds-cpu` | RDS 평균 CPU가 최근 5분 중 3분 이상 80% 초과 |

p95는 값이 작은 순서로 정렬했을 때 95% 지점의 값이다. 표본이 너무 적으면 응답 시간 경보는 현재 상태를 유지한다. 위 경보의 지표와 상태는 CloudWatch 콘솔에서 확인한다. SNS와 Slack 알림 연동은 별도 작업으로 남겨 둔다.

## 시드니에서 검증할 순서

1. 비용 확인 후 `terraform/data`를 먼저 적용한다. `terraform/app`의 `image_tag`에는 ECR에 실제로 존재하는 ARM64 이미지 태그를 지정한다. 이전 실습에서 이미지를 지웠다면 [CI/CD 기록](07-cicd.md)에 따라 다시 준비한다. RDS 출력이 있어야 앱의 실제 `terraform plan`을 마칠 수 있다.
2. `aws ecs list-tasks`, `aws ecs describe-tasks`로 실행 중인 작업 2개의 `availabilityZone`을 확인한다. ALB 대상 그룹에서 두 작업이 `healthy`인지 확인한다.
3. ALB의 `/actuator/health`에 1초 간격으로 요청을 보내며 대상 작업 하나를 중지한다. 요청 성공률, 새 작업이 정상으로 전환될 때까지 걸린 시간, 최종 AZ 분포를 기록한다.
4. ALB에 단계적으로 부하를 주고 CloudWatch의 ECS CPU 그래프와 Application Auto Scaling 활동에서 작업 수가 늘어나는지 확인한다. 부하를 끄고 안정화 후 작업 수가 2로 돌아오는지 확인한다.
5. CloudWatch에서 세 경보의 지표와 상태 이력을 확인한다. 기동 시간을 비교할 때는 같은 이미지로 두 사양에서 Spring Boot `Started` 로그를 비교한다. ECS를 만든 뒤 GitHub Actions 배포를 실행했다면 Terraform 계획에서 의도한 이미지가 유지되는지 먼저 확인한다.
6. [RDS 정리 절차](06-rds.md)에 따라 app, data 순서로 삭제한다. 앱을 비교 사양으로 실행했다면 app 삭제에도 같은 `task_vcpu`를 전달한다. AWS CLI로 경보, 자동 확장 대상, ECS 작업과 작업 정의, ALB, NAT, RDS, 최종 스냅샷, ECR 이미지가 정리됐는지 확인한다.

## 실습 결과 (2026-11-19)

- `b73a13a`로 실행한 [GitHub Actions](https://github.com/yeopjoonhyun/aws-terraform-springboot-infra/actions/runs/44428057578)가 성공했고, ECR의 ARM64 이미지로 배포했다. 실제 Terraform 계획과 적용에서 `data` 리소스 3개, `app` 리소스 17개가 추가됐다.
- 초기 기동 중 요청 한 건이 HTTP 502를 받았다. ECS의 `RUNNING`과 ALB의 `healthy`에는 시간차가 있었다. 단일 작업 중단은 두 대상이 모두 `healthy`가 된 뒤에 시작했다.
- `ap-southeast-2a`, `ap-southeast-2b`에 작업 하나씩 배치됐다. `2b` 작업 하나를 중지하는 동안 ALB의 `/actuator/health`에 보낸 요청 130건이 모두 HTTP 200이었다. 중지 요청부터 교체 작업이 동일 AZ에서 `healthy`가 되기까지 약 2분 49초 걸렸다.
- CloudWatch에서 RDS CPU, 앱 p95 응답 시간, ALB 5xx 데이터가 들어온 것을 확인했다. DB 조회 부하에서 ALB 5xx가 분당 26건, 934건, 5,172건으로 집계됐고, 5xx 경보가 `OK`에서 `ALARM`으로 바뀌었다.
- DB 조회에 동시 요청을 보냈을 때 Hikari 연결 풀 10개가 사용 중이었고, 연결을 기다린 요청이 30초 뒤 타임아웃됐다. ALB 헬스체크 실패가 이어지자 ECS가 작업을 교체했다. 이때 서비스 목표 작업 수는 2였고 자동 확장 활동은 없었다. 교체 작업의 DB 읽기 타임아웃도 관찰됐으며, 같은 시간대에 RDS가 자체 복구 이벤트를 기록했다.
- 실습 RDS를 재부팅한 뒤 ECS 작업이 다시 두 AZ에 하나씩 `healthy`가 됐다. Spring Boot 로그 기준 0.25 vCPU에서 초기 작업은 39.0초와 79.0초, 중단 후 교체 작업은 73.9초였다. 0.5 vCPU에서는 35.6초와 37.3초였다. 표본이 적고 메모리와 DB 상태도 달라져 CPU만의 효과는 분리하지 못했다.
- 복구 후 DB를 조회하지 않는 `/actuator/info`에 동시 요청을 단계적으로 올렸다. 총 380,443건이 HTTP 200이었다. 조회한 분당 ECS 평균 CPU 사용률은 최고 45.9%였고 두 대상은 정상 상태를 유지했다. AWS에서 최소 2개, 최대 4개, CPU 목표 60% 정책이 등록된 것을 확인했다. 실습 중 자동 확장 활동은 0건이어서 실제 확장과 축소 검증을 남겼다.
- 적용 시작부터 삭제 완료까지 `app`은 약 40분, `data`는 약 55분 걸렸다. AWS CLI로 RDS, 스냅샷, 자동 백업, 관리 비밀, ALB, NAT, EIP, ECS 작업과 활성 작업 정의, 자동 확장 대상과 정책, CloudWatch 경보와 로그 그룹, ECR 이미지가 모두 0개인지 확인했다. `app`, `data` Terraform state도 비었고 `network` 계획은 변경 사항이 없었다.

## 자동 확장·축소 재검증

- DB 요청 없이 작업 내부에서 일정 시간 CPU 부하를 만들고, 종료 후 AWS의 확장·축소 활동과 실제 작업 수를 확인하는 실습을 준비했다.
- 이번 시드니 배포에서 AWS Organizations의 서비스 제어 정책(SCP)이 `rds:CreateDBInstance`를 명시적으로 거부했다. DB 없는 H2 구성에서도 같은 정책이 `elasticloadbalancing:CreateLoadBalancer`와 `ec2:CreateNatGateway`를 거부했다. ECS 서비스를 시작할 수 없어 자동 확장·축소 실측은 보류했다.
- 부분 생성된 데이터 리소스 1개와 앱 리소스 7개를 Terraform으로 삭제하고, 재실행한 GitHub Actions가 올린 ECR 이미지 1개도 삭제했다. AWS CLI로 남은 실습 리소스와 이미지가 0개임을 확인했다. `app`, `data` 상태도 비었고 `network` 계획은 변경 사항이 없었다.

### AWS 배포 전 설정 검증

깨끗한 체크아웃에서 저장소 루트 기준으로 실행한다.

```bash
terraform -chdir=terraform/app init -backend=false
terraform -chdir=terraform/app test
```

AWS 제공자와 원격 상태 출력을 모의 값으로 대체한다. 초기 작업 2개, 두 서브넷의 AZ 재분배, 2~4개 범위, 평균 CPU 목표 60%, 축소 가능 여부를 검사한다. 실제 AWS에서 작업 수가 변하는지는 실습으로 확인한다.
