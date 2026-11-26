# 9단계 EKS 전환

같은 Spring Boot 앱과 RDS MySQL을 ECS Fargate에서 실행했던 구성과 비교한다. EKS에서는 관리형 노드 그룹의 ARM64 EC2 두 대에 앱 파드 두 개를 실행한다. 파드는 쿠버네티스가 컨테이너를 배치하는 단위다.

## 구성 비교

| 항목 | ECS Fargate | EKS |
|---|---|---|
| 실행 단위 | ECS 서비스가 작업을 관리 | Deployment가 파드를 관리. 관리형 노드 그룹이 EC2를 관리 |
| 외부 트래픽 | Terraform이 ALB와 대상 그룹 생성 | AWS Load Balancer Controller가 Ingress 설정을 읽고 ALB와 대상 그룹 생성 |
| 앱 확장 | CloudWatch와 Application Auto Scaling이 CPU 60% 기준으로 작업 2~4개 관리 | Metrics Server와 HPA가 CPU 요청량 대비 60% 기준으로 파드 2~4개 관리. 노드 그룹의 목표 수는 2대 |
| DB 접속 | ECS 작업의 비밀 주입 기능으로 Secrets Manager에서 접속 정보 가져옴 | 배포 스크립트가 Secrets Manager 값을 쿠버네티스 Secret으로 넣음 |
| 정리 순서 | Terraform으로 앱 루트를 정리한 뒤 DB 삭제 | Ingress와 ALB를 먼저 정리한 뒤 EKS와 DB 삭제 |

## 시드니 실습 순서

1. ECS 앱 루트가 꺼져 있는지 확인한다. ECS와 EKS는 같은 프라이빗 서브넷의 기본 경로에 각각 NAT Gateway를 연결하므로 동시에 켜지 않는다.
2. 개인 계정과 시드니 리전을 확인한다. EKS 루트의 계정 번호는 Git이 무시하는 `terraform.tfvars`로 지정한다. ARM64 앱 이미지가 개인 ECR에 올라가 있어야 한다.
3. `terraform/data`와 `terraform/eks`를 적용한다. 임시 실습 DB에 `-var deletion_protection=false`를 전달하면 삭제 방지를 끄기 위한 후속 적용이 필요 없다.
4. 개인 클러스터 전용 kubeconfig를 지정한 다음 `k8s/deploy.sh <이미지 태그>`를 실행한다. 로드밸런서에서 `/actuator/health`를 확인하고 `/api/notes`로 노트 생성·조회·삭제를 검증한다.
5. 같은 kubeconfig로 `k8s/teardown.sh`를 실행해 Ingress가 만든 ALB가 삭제될 때까지 기다린다. EKS와 RDS 루트를 삭제한다. [RDS 정리 절차](06-rds.md)에 따라 최종 스냅샷도 삭제하고, 실습용 ECR 이미지 태그를 정리한다.
6. AWS CLI로 EKS, 노드, ALB, 대상 그룹, NAT, 공인 IP, RDS, 스냅샷, 실습용 이미지가 남았는지 확인한다. 네트워크와 레지스트리 루트는 다음 실습에도 재사용한다.

## 실습 결과 (2026-11-26)

- 시드니에서 EKS 1.37 표준 지원으로 EKS 루트 22개, RDS 루트 3개를 적용했다. 제어 플레인 생성은 8분 35초 걸렸다.
- ARM64 `t4g.medium` 노드 2대가 `ap-southeast-2a`와 `ap-southeast-2b`에 한 대씩 Ready였다. 앱 파드 2개가 Ready가 됐고 ALB 대상 2개도 모두 `healthy`였다.
- ALB로 `/actuator/health`를 호출해 HTTP 200과 `UP`을 확인했다. RDS 노트 API는 생성 201, 조회 200, 삭제 204, 삭제 후 조회 404를 돌려줬다.
- 처음에는 맥의 기본 DNS 조회에서 새 ALB 주소를 찾지 못했다. `dig` 응답에 나온 IPv4를 `curl --resolve`에 넘겨 DNS 설정 변경 없이 같은 ALB를 검증했다.
- HPA가 CPU 지표 2%를 읽었다. 목표는 60%, 파드는 2~4개다. 부하를 줘 실제로 파드가 늘고 줄어드는 검증은 10단계에 남겼다.
- 생성 시작부터 정리 완료까지 24분 12초 걸렸다. ALB를 먼저 삭제한 뒤 EKS와 RDS 루트를 정리했다. AWS CLI로 클러스터, 노드, EBS, ALB와 대상 그룹, NAT, 공인 IP, RDS, 스냅샷, 자동 백업, 관리 비밀, 경보, 실습용 ECR 이미지가 모두 0개임을 확인했다. EKS와 RDS의 Terraform state도 비었고 네트워크 실행 계획에 변경 사항이 없었다.
