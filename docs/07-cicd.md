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

## AWS 접근: OIDC 대신 최소 권한 키 (차선책)
원래 계획은 OIDC였다. GitHub이 실행할 때마다 짧게 쓰는 임시 자격 증명을 받아서, 저장소에 키를 둘 필요가 없다.
그런데 이 계정은 AWS Organizations의 멤버 계정이고, 조직 SCP가 `iam:*OpenIDConnectProvider*`를 명시적으로 거부한다.
- 조회(`GetOpenIDConnectProvider`, `ListOpenIDConnectProviders`)와 생성(`CreateOpenIDConnectProvider`) 모두 `explicit deny in a service control policy`
- SCP는 관리 계정에서만 고칠 수 있다. 관리 계정은 내 Gmail로 등록돼 있지만 로그인이 되지 않아 지금은 풀 수 없다

그래서 배포 전용 IAM 사용자 `aws-tf-springboot-github-deployer`를 만들고 권한을 좁혔다 (`terraform/registry/deployer.tf`).

| 허용 | 범위 |
|---|---|
| ECR 로그인 토큰 | `*` (API가 리소스 지정을 지원하지 않음) |
| 이미지 푸시, 태그 조회 | 이 ECR 저장소 1개 |
| 서비스 조회, 갱신 | 이 ECS 서비스 1개 (ARN을 이름으로 미리 고정. app을 지웠다 다시 만들어도 같다) |
| 작업 정의 조회, 등록 | `*` (API가 리소스 지정을 지원하지 않음) |
| 실행 역할 넘기기 (`iam:PassRole`) | 실행 역할 1개, ECS 작업에만 (`iam:PassedToService` 조건) |

- 키는 Terraform으로 만들지 않았다. `aws_iam_access_key`를 쓰면 비밀 키가 state 파일에 남는다. 키는 콘솔이나 CLI로 만들어 GitHub 비밀값에 바로 넣었다.
- 관리자 키(`terraform-admin`)는 GitHub에 넣지 않는다. 새어 나가면 계정 전체가 위험하다.
- OIDC가 허용되면 이 사용자와 키를 지우고 OIDC 역할로 바꾼다.

## 검증 결과 (2026-11-17)
- CI 첫 실행: 앱 테스트, ARM 이미지 빌드, Terraform 검사 모두 성공 (각 약 50초).
- CD 첫 실행: ECR에 `1c2735c` 푸시 성공. app이 꺼져 있어 배포는 계획대로 건너뜀(`::notice::`). 공개 로그에 계정 번호 노출 0회.
- 남은 검증: app이 켜진 상태에서 main 푸시 -> ECS가 새 이미지로 바뀌는지.

## 알려진 한계
- CD가 등록한 작업 정의는 Terraform이 모른다. 같은 세션에서 `terraform apply`를 다시 하면 `image_tag` 변수 값으로 되돌린다. app은 쓸 때만 켜므로 apply할 때 최신 SHA를 넘긴다.
- 장기 키라서 주기적으로 바꿔야 한다. 새 키를 만들고 GitHub 비밀값을 바꾼 뒤 옛 키를 지운다.
