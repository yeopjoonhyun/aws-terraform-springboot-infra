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
