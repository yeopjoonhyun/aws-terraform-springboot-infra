# AWS 실습 비용

NAT Gateway, ALB, RDS는 실습 때 생성하고 검증이 끝나면 삭제했다. ECS와 EKS는 같은 프라이빗 앱 서브넷의 기본 경로를 사용하므로 한 번에 하나만 켰다. [삭제 순서와 점검](teardown.md)

## 실습 기록

| 일자 | 검증 | 사용 시간과 비용 기록 |
| --- | --- | --- |
| 11월 12일 | 첫 ECS·ALB 배포 | 앱과 네트워크 출구 약 10분, 당시 추정 약 **$0.12** |
| 11월 16일 | ECS에서 RDS 연결 | RDS 약 37분, 앱 약 19분, 당시 추정 약 **$0.15** |
| 11월 24일 | ECS 자동 확장과 축소 | RDS 약 59분, 앱 약 44분, 당시 추정 약 **$0.20** |
| 11월 26일 | 첫 EKS·RDS 배포 | 생성 시작부터 정리 완료까지 **24분 12초** |
| 11월 27일 | Argo CD 배포·되돌리기, 부하·경보 검증 | EKS와 RDS 적용 시작부터 삭제 완료까지 약 **61분** |

위 금액은 개발 일지의 개별 실습 추정치다. 11월 24일 청구 화면에는 당시 계정 월 누계 **$0.83**이 표시됐고, 개발 일지에는 크레딧으로 처리될 예정이라고 기록했다. 11월 28일 AWS Settings에서도 계정 전체 월 누계까지 확인했다. 프로젝트 태그로 구분한 청구액은 별도 로그인이 필요한 상세 화면에 있어 확인하지 못했다. [11월 24일 비용 기록](devlog.md#2026-11-24), [EKS 실습 시간](09-eks.md#실습-결과-2026-11-26), [GitOps 실습 시간](10-gitops-monitoring.md#실습-결과-2026-11-27)

## ECS 구성을 한 달 유지할 경우

2026년 11월 28일 확인한 시드니(`ap-southeast-2`) 온디맨드 단가와 월 730시간 기준이다. Fargate 작업 2개를 각각 0.25 vCPU, 0.5 GiB로 유지하고, 공인 IPv4는 두 AZ의 ALB에 2개와 NAT에 1개를 가정했다.

| 항목 | 단가와 사용량 | 월 추정 USD |
| --- | --- | ---: |
| Fargate Linux ARM64 | vCPU 시간당 $0.03885, 메모리 GiB 시간당 $0.00426, 작업 2개. [시드니 ECS 요금표](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonECS/current/ap-southeast-2/index.json) | $17.29 |
| NAT Gateway | 시간당 $0.059, 1개. [시드니 EC2 요금표](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/ap-southeast-2/index.json) | $43.07 |
| Application Load Balancer | 기본 시간당 $0.0252, 1개. [시드니 ALB 요금표](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSELB/current/ap-southeast-2/index.json) | $18.40 |
| 공인 IPv4 | 개당 시간당 $0.005, 3개. [시드니 VPC 요금표](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonVPC/current/ap-southeast-2/index.json) | $10.95 |
| RDS MySQL `db.t4g.micro` | Single-AZ, 시간당 $0.025. [시드니 RDS 요금표](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonRDS/current/ap-southeast-2/index.json) | $18.25 |
| RDS gp3 스토리지 | GB·월당 $0.138 × 20 GB. [시드니 RDS 요금표](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonRDS/current/ap-southeast-2/index.json) | $2.76 |
| **기본 구성 합계** | **시간당 약 $0.152** | **$110.72** |

기본 구성 추정치에는 ALB 사용량(LCU), NAT 처리량, 데이터 전송, 로그와 관리 비밀, 추가 스냅샷, 세금 및 크레딧을 반영하지 않았다. 시드니에서 NAT 처리량은 GB당 $0.059, ALB 사용량은 LCU 시간당 $0.008이 추가된다. NAT 기본료와 RDS 인스턴스·스토리지만 합해도 월 **$64.08**이므로 두 리소스부터 가동 시간을 줄였다. [시드니 EC2 요금표](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/ap-southeast-2/index.json), [시드니 ALB 요금표](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSELB/current/ap-southeast-2/index.json)
