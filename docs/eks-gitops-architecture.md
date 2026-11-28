# EKS·GitOps 아키텍처

시드니 리전에서 검증한 Spring Boot 노트 앱 구성이다. GitOps는 Git에 기록한 배포 상태를 Argo CD가 클러스터에 맞추는 방식이다.

## 사용자 요청 경로

```mermaid
flowchart LR
    accTitle: EKS 사용자 요청 경로
    accDescr: 사용자는 퍼블릭 ALB에 접속한다. ALB는 프라이빗 EKS의 파드 IP에 요청을 전달하고, 파드는 프라이빗 RDS MySQL에 접속한다.

    user([사용자])
    subgraph vpc["시드니 VPC · ap-southeast-2"]
        subgraph public["퍼블릭 · 두 AZ"]
            alb["ALB<br/>파드 IP로 전달"]
        end
        subgraph privateApp["프라이빗 앱 · 두 AZ"]
            pods["EKS · Spring Boot<br/>앱 파드 2~4개"]
        end
        subgraph privateDb["프라이빗 DB"]
            db[("RDS MySQL<br/>단일 AZ")]
        end

        alb -->|HTTP 8080| pods
        pods -->|MySQL 3306| db
    end
    user -->|HTTP 80| alb

    classDef entry fill:#e7f0ff,stroke:#3a64a2,color:#132d51
    classDef compute fill:#e5f6ee,stroke:#34735a,color:#153c2d
    classDef database fill:#f3eaff,stroke:#725398,color:#382451
    class alb entry
    class pods compute
    class db database
```

AWS Load Balancer Controller가 Ingress 설정을 읽어 ALB를 만든다. ALB는 `/readyz`를 통과한 파드의 IP로 직접 요청을 보낸다. 앱 파드는 두 가용 영역에 걸쳐 배치된 ARM64 노드에서 실행한다. HPA는 Metrics Server의 CPU 지표를 읽고 평균 사용률 60%를 목표로 파드를 2~4개 사이에서 조절한다. [EKS 구성과 검증](09-eks.md), [GitOps 실측](10-gitops-monitoring.md)

## Git 커밋에서 EKS 배포까지

```mermaid
sequenceDiagram
    accTitle: EKS GitOps 배포 경로
    accDescr: 인프라 저장소의 main 푸시로 GitHub Actions가 이미지를 ECR에 올리고 매니페스트 저장소의 태그를 바꾼다. Argo CD가 변경을 읽고 EKS의 Deployment를 갱신한다.

    participant Infra as 인프라 저장소
    participant CI as GitHub Actions
    participant ECR as Amazon ECR
    participant Git as 매니페스트 저장소
    participant Argo as Argo CD
    participant EKS as EKS

    Infra->>CI: main 푸시
    Note over CI: 검사 통과 후 OIDC로 AWS 임시 권한 획득
    CI->>ECR: ARM64 이미지 업로드
    CI->>Git: 배포 키로 newTag 커밋
    Argo->>Git: main의 overlays/prod 확인
    Git-->>Argo: 매니페스트와 이미지 태그
    Argo->>EKS: Deployment 동기화
    EKS->>ECR: 노드가 NAT를 거쳐 이미지 요청
    ECR-->>EKS: ARM64 이미지 반환
    Note over EKS: 새 파드 기동
```

CI가 바꾸는 태그는 매니페스트 저장소의 `base/kustomization.yaml`에 있다. Argo CD Application은 배포할 때 이미지 이름을 ECR 주소로 바꾸고 base의 태그를 사용한다. 되돌릴 때는 매니페스트 저장소에서 태그 커밋을 `git revert`한다. [매니페스트 저장소](https://github.com/yeopjoonhyun/aws-tf-springboot-manifests), [Argo CD Application 설정](../k8s/argocd-app.yaml), [배포와 되돌리기 실측](10-gitops-monitoring.md#gitops-배포-되돌리기-prestop-비교)

## 앱 지표와 Slack 경보

```mermaid
flowchart LR
    accTitle: Prometheus에서 Slack까지 이어지는 경보 경로
    accDescr: Prometheus는 ServiceMonitor 설정에 따라 앱 관리 포트 8081에서 지표를 수집한다. 경보 조건을 만족하면 Alertmanager가 Slack으로 알린다.

    subgraph cluster["EKS 클러스터"]
        app["Spring Boot 파드<br/>8081 · /actuator/prometheus"]
        prom["Prometheus<br/>지표 수집 · 규칙 평가"]
        alerts["Alertmanager<br/>알림 묶음 · 경로 선택"]
        prom -->|15초마다 수집| app
        prom -->|경보 상태 전달| alerts
    end
    alerts -->|웹훅| slack["Slack"]

    classDef compute fill:#e5f6ee,stroke:#34735a,color:#153c2d
    classDef monitor fill:#e7f0ff,stroke:#3a64a2,color:#132d51
    class app compute
    class prom,alerts monitor
```

ServiceMonitor가 수집 대상을 고르고 PrometheusRule이 경보 기준을 정한다. 지표는 클러스터 내부의 8081에서 수집하며, 외부 ALB는 앱 포트 8080으로 요청을 전달한다. Alertmanager는 `saa-notes` 네임스페이스의 경보를 Slack으로 보낸다. 웹훅은 배포할 때 SSM SecureString에서 쿠버네티스 Secret으로 옮겨 파일로 읽는다. [모니터링 설정](../k8s/monitoring-values.yaml), [경보 규칙과 실측](10-gitops-monitoring.md)
