# ECS Fargate 아키텍처

시드니 리전(`ap-southeast-2`)에서 실행한 Spring Boot 노트 앱 구성이다. AZ는 리전 안에서 장애를 분리하는 가용 영역이다.

## 사용자 요청 경로

```mermaid
flowchart LR
    accTitle: ECS Fargate 사용자 요청 경로
    accDescr: 사용자가 두 가용 영역에 걸친 ALB에 접속한다. ALB는 프라이빗 앱 서브넷의 Fargate 작업에 요청을 보내고, 작업은 프라이빗 DB 서브넷의 RDS MySQL에 접속한다.

    user([사용자])

    subgraph vpc["시드니 VPC · ap-southeast-2"]
        subgraph public["퍼블릭 · 두 AZ"]
            alb["ALB<br/>정상 작업으로 전달"]
        end

        subgraph privateApp["프라이빗 앱"]
            taskA["Fargate · AZ A<br/>Spring Boot"]
            taskB["Fargate · AZ B<br/>Spring Boot"]
        end

        subgraph privateDb["프라이빗 DB"]
            mysql[("RDS MySQL<br/>단일 AZ")]
        end

        alb -->|HTTP 8080| taskA
        alb -->|HTTP 8080| taskB
        taskA -->|MySQL 3306| mysql
        taskB -->|MySQL 3306| mysql
    end

    user -->|HTTP 80| alb

    classDef entry fill:#e7f0ff,stroke:#3a64a2,color:#132d51
    classDef compute fill:#e5f6ee,stroke:#34735a,color:#153c2d
    classDef database fill:#f3eaff,stroke:#725398,color:#382451
    class alb entry
    class taskA,taskB compute
    class mysql database
```

- ALB(Application Load Balancer)는 `/actuator/health`가 200을 반환하는 작업으로 요청을 보낸다. Fargate 작업은 공인 IP 없이 ARM64 컨테이너를 실행한다. ECS는 작업 2개로 시작하고, 평균 CPU 사용률 60%를 목표로 2~4개 사이에서 확장하거나 축소한다. [고가용성 실측](08-ha-observability.md)
- RDS 서브넷 그룹은 두 AZ에 걸쳐 있지만 DB 인스턴스는 한 AZ에 있다. 앱이 AWS 서비스에 접속할 때 쓰는 NAT Gateway도 비용을 줄이기 위해 AZ A에 한 개만 둔다. [네트워크 구성](02-network-design.md), [RDS 설정](06-rds.md)

## GitHub Actions 배포 경로

```mermaid
sequenceDiagram
    accTitle: GitHub Actions에서 ECS로 이어지는 배포 경로
    accDescr: GitHub Actions가 main 푸시의 검증을 마친 뒤 AWS STS의 임시 권한으로 ECR에 이미지를 올린다. ECS 서비스가 실행 중이면 새 작업 정의를 배포한다. Fargate 작업은 NAT를 경유해 이미지를 받는다.

    participant CI as GitHub Actions
    participant STS as AWS STS
    participant ECR as Amazon ECR
    participant ECS as ECS 서비스
    participant Task as Fargate 작업

    Note over CI: main 푸시 · 테스트와 빌드 검사 통과
    CI->>STS: GitHub OIDC 토큰으로 역할 요청
    STS-->>CI: 임시 AWS 자격 증명
    CI->>ECR: ARM64 이미지 업로드 · 커밋 SHA 7자리 태그
    opt ECS 서비스가 ACTIVE
        CI->>ECS: 작업 정의 등록 · 서비스 갱신
        ECS->>Task: 새 작업 시작
        Task->>ECR: NAT 경유 이미지 요청
        ECR-->>Task: ARM64 이미지
    end
```

작업 시작 시 ECS는 실행 역할로 Secrets Manager의 DB 접속 정보를 읽어 컨테이너에 전달한다. 앱 로그는 CloudWatch Logs로 보낸다. ECS 서비스가 꺼져 있어도 이미지 업로드는 진행하고 ECS 갱신은 건너뛴다. [CI/CD 구현](07-cicd.md), [워크플로](../.github/workflows/ci.yml)
