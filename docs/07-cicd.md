# 07. GitHub Actions CI/CD

## 흐름
```
PR      -> 앱 테스트 / ARM 이미지 빌드 / Terraform fmt, validate      (AWS 접속 없음, 비밀값 안 씀)
main    -> 위 3개 통과 -> ECR에 커밋 SHA 7자리 태그로 푸시 -> app이 켜져 있으면 ECS 배포
```
워크플로는 `.github/workflows/ci.yml` 하나다.

## 설계 결정
| 결정 | 이유 |
|---|---|
| ECR을 `terraform/registry` 루트로 분리 | app은 쓸 때만 켜고 지운다. ECR이 app에 있으면 평소에는 CI가 이미지를 올릴 곳이 없다. 빈 저장소는 무료, 이미지는 GB당 월 $0.10 |
| ARM 러너(`ubuntu-24.04-arm`)에서 빌드 | ECS가 ARM64다. 에뮬레이션 없이 같은 구조에서 빌드한다 |
| 테스트는 `gradle:9-jdk21` 컨테이너에서 | Dockerfile 빌드 단계와 같은 이미지. 저장소에 Gradle Wrapper가 없다 |
| 액션을 커밋 해시로 고정 | `v7` 같은 태그는 나중에 다른 코드를 가리킬 수 있다 (공급망 공격 방지) |
| `permissions: contents: read` | 워크플로의 GitHub 토큰은 읽기만 한다 |
| 계정 번호 마스킹 (`::add-mask::`) | Public 저장소라 실행 로그도 공개된다. 로그에서 계정 번호 노출 0회 확인 |
| 같은 태그가 있으면 푸시 건너뜀 | ECR이 IMMUTABLE이라 재실행하면 푸시가 실패한다 |
| app이 꺼져 있으면 배포 건너뜀 (실패 아님) | 비용 때문에 app을 평소에 지워 둔다 |
| 배포는 현재 작업 정의를 복사하고 이미지만 교체 | 환경 변수, 비밀, 실행 역할은 Terraform이 정한 그대로 유지한다 |

## AWS 접근: OIDC 역할 (2026-11-25부터)
GitHub Actions는 장기 키 없이 OIDC로 AWS에 들어간다. GitHub이 실행마다 서명한 토큰을 주고, AWS가 그 토큰을 확인한 뒤 1시간짜리 임시 키를 내준다. 저장소에 둔 비밀값은 역할 ARN(`AWS_DEPLOY_ROLE_ARN`) 하나다. 계정 번호가 들어 있어서 비밀값에 두었고, 키가 아니라서 새어 나가도 그것만으로는 들어올 수 없다.

- OIDC 공급자와 역할 `aws-tf-springboot-github-deployer`는 `terraform/registry/deployer.tf`에 있다.
- 역할은 **이 레포의 main 브랜치** 실행만 맡을 수 있다. 토큰의 `sub`가 `repo:소유자@ID/레포@ID:ref:refs/heads/main`과 같아야 한다. PR, 다른 브랜치, 다른 레포는 거부된다. ID까지 비교하므로 같은 이름으로 레포를 다시 만들어도 맡을 수 없다.
- `id-token: write` 권한은 배포 작업에만 준다.

| 허용 | 범위 |
|---|---|
| ECR 로그인 토큰 | `*` (API가 리소스 지정을 지원하지 않음) |
| 이미지 푸시, 태그 조회 | 이 ECR 저장소 1개 |
| 서비스 조회, 갱신 | 이 ECS 서비스 1개 (ARN을 이름으로 미리 고정. app을 지웠다 다시 만들어도 같다) |
| 작업 정의 조회, 등록 | `*` (API가 리소스 지정을 지원하지 않음) |
| 실행 역할 넘기기 (`iam:PassRole`) | 실행 역할 1개, ECS 작업에만 (`iam:PassedToService` 조건) |

- 관리자 키(`terraform-admin`)는 GitHub에 넣지 않는다. 새어 나가면 계정 전체가 위험하다.

### 장기 키에서 OIDC로 바꾼 과정
- 11/17: OIDC 공급자 조회와 생성이 `explicit deny in a service control policy`로 거부됐다. 거부한 정책은 새 가입 방식(프로젝트) 계정에 붙는 관리형 SCP였다. 공식 문서의 플랜 SCP에 `DenyIAMRestrictedActions`(`iam:*Provider*` 포함)가 있다. 그래서 같은 권한의 IAM 사용자와 장기 키로 대신했다. 키는 비밀 키가 state에 남지 않게 Terraform 밖에서 만들었다.
- 11/24: 같은 조회가 허용되는 것을 확인했다(`NoSuchEntity`). 정책이 왜 바뀌었는지는 확인하지 못했다.
- 11/25: 공급자와 역할을 만들고, 사용자와 역할이 같은 권한 정의를 쓰게 한 상태에서 CI를 역할로 바꿨다. 첫 실행은 `Not authorized to perform sts:AssumeRoleWithWebIdentity`로 실패했다. CloudTrail에서 토큰의 실제 `sub`를 보니 GitHub이 소유자와 레포 이름 뒤에 ID를 붙이고 있었다(`소유자@ID/레포@ID`). 조건을 그 형식으로 고치자 성공했다. CI 로그의 역할 ID가 새 역할과 같았고, 옛 키의 마지막 사용은 전날이었다. 그 뒤 키, 사용자, GitHub 비밀값 2개를 지웠다.

## 검증 결과 (2026-11-17)
- CI 첫 실행: 앱 테스트, ARM 이미지 빌드, Terraform 검사 모두 성공 (각 약 50초).
- CD 첫 실행: ECR에 `1c2735c` 푸시 성공. app이 꺼져 있어 배포는 계획대로 건너뜀(`::notice::`). 공개 로그에 계정 번호 노출 0회.

### 켜진 ECS에 자동 배포 (2026-11-18)
1. `deb4599`(빌드 정보 표시)를 푸시. app이 꺼져 있어 CD는 ECR 푸시만 하고 배포를 건너뜀.
2. data, app을 `image_tag=deb4599`로 켬. `/actuator/info`가 `version 0.0.1`.
3. `599a8e3`(버전 0.0.2)를 푸시. CD가 작업 정의 새 버전을 등록하고 서비스를 갱신.
4. 배포 중 1초마다 요청: **186번 모두 200, 중단 0회**. 버전은 0.0.1 -> 0.0.2. 몇 초 동안 두 버전이 섞여 응답했는데, ECS가 새 작업을 먼저 띄우고 옛 작업을 나중에 내리는 롤링 배포라서 ALB가 둘 다에 나눠 보낸 것이다.
5. 서비스의 작업 정의 이미지 태그가 `599a8e3`인 것을 확인.

## 알려진 한계
- CD가 등록한 작업 정의는 Terraform이 모른다. 같은 세션에서 `terraform apply`를 다시 하면 `image_tag` 변수 값으로 되돌린다. app은 쓸 때만 켜므로 apply할 때 최신 SHA를 넘긴다.
- app을 destroy해도 CD가 등록한 작업 정의 버전은 Terraform이 몰라서 남는다(무료). 정리할 때 `aws ecs deregister-task-definition`으로 내린다.
