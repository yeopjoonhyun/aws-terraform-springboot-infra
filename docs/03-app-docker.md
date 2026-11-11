# 03. 앱 Docker화

## 앱: SAA 학습 노트 API (`app/`)
AWS SAA 학습 내용을 저장하고 조회하는 작은 REST API입니다. 배포 파이프라인에 필요한 최소 기능만 담았습니다.

| 항목 | 내용 |
|---|---|
| 스택 | Spring Boot 4.1.2, Java 21, Gradle, Spring Web, JPA, Validation, Actuator |
| DB | 기본은 메모리 DB(H2). RDS 단계에서 환경 변수로 MySQL로 교체 예정 |
| 포트 | 8080 |

### API
| 메서드 | 경로 | 설명 |
|---|---|---|
| POST | `/api/notes` | 노트 생성 (제목, 분류, 내용 필수) |
| GET | `/api/notes?category=VPC` | 목록 조회 (분류 필터 선택) |
| GET | `/api/notes/{id}` | 단건 조회, 없으면 404 |
| PUT | `/api/notes/{id}` | 수정 |
| DELETE | `/api/notes/{id}` | 삭제 |
| GET | `/actuator/health` | 상태 확인 (ALB 헬스체크용) |

입력 검증을 위반하면 400, 없는 노트는 404를 반환합니다.

## Dockerfile 설계
멀티 스테이지 빌드로 구성했습니다.
1. **빌드 단계** (`gradle:9-jdk21`): 컨테이너 안에서 jar를 만든다. 로컬에 Gradle이 없어도 되고, CI에서도 같은 방식으로 재현된다.
2. **실행 단계** (`eclipse-temurin:21-jre-alpine`): JRE와 jar만 담아 최종 이미지에서 빌드 도구를 뺀다.
3. **비root 사용자**(`appuser`)로 실행해 컨테이너가 침해되어도 권한을 제한한다.
4. 빌드 설정 파일을 먼저 복사해 의존성 다운로드 레이어를 캐시한다.

## 로컬 검증 (Colima + Docker)
```bash
cd app
docker build -t saa-notes:local .
docker run -d --name saa-notes-test -p 18080:8080 saa-notes:local
curl http://localhost:18080/actuator/health
docker rm -f saa-notes-test
```

검증 결과
- 단위 테스트 1개 통과 (저장한 노트를 분류로 조회)
- 헬스체크 `UP`, 생성/조회 정상, 빈 제목 400, 없는 노트 404
- 실행 사용자 `appuser` 확인
- 이미지 크기 약 583MB → 경량화 후 393MB (아래 참고)

## 베이스 이미지 경량화와 취약점 조치 (2026-11-11)
같은 jar(Spring Boot 4.1.0)로 실행 단계 베이스만 바꿔 빌드하고, 같은 도구(Trivy 0.76.2)로 검사해 비교했다.

| 베이스 | 크기 | CRITICAL | HIGH | MEDIUM | LOW | OS 패키지 HIGH 이상 |
|---|---|---|---|---|---|---|
| `eclipse-temurin:21-jre` (Ubuntu) | 583MB | 7 | 8 | 62 | 4 | apt, libapt-pkg |
| `eclipse-temurin:21-jre-alpine` | 393MB | 7 | 6 | 7 | 0 | 없음 |
| `distroless/java21-debian13:nonroot` | 378MB | 7 | 14 | 53 | 23 | libexpat1, libuuid1 |

- 세 이미지 모두 헬스체크, 생성, 404, 비root 실행, 기동 시간(약 4초)이 같았다.
- Alpine을 골랐다. Distroless보다 15MB 크지만 OS 패키지 취약점이 가장 적고, 셸이 있어 디버깅이 쉽다.
- CRITICAL 7개는 세 이미지에 똑같이 있었다. 출처는 OS가 아니라 앱 jar 안의 라이브러리(Tomcat 11.0.22, Spring MVC 7.0.8, Jackson 3.1.4)였다. 베이스 이미지로는 해결되지 않는다.
- Spring Boot를 4.1.0에서 4.1.2로 올려 Tomcat 11.0.27, Spring 7.0.10, Jackson 3.1.7로 갱신했다(모두 스캔이 요구한 수정 버전 이상).

**결과:** 583MB에서 393MB로 33% 줄었고, CRITICAL 7과 HIGH 8에서 **MEDIUM 1**(Alpine의 zlib, 상위 이미지 갱신 시 해소)만 남았다. 테스트와 API 검증도 다시 통과했다.

**배운 것:** ECR 기본 스캔은 OS 패키지만 검사해서 jar 안의 라이브러리 취약점을 놓쳤다. 애플리케이션 의존성까지 보려면 Trivy 같은 도구나 Amazon Inspector 고급 스캔이 필요하다.

## 다음 단계
- ECR 저장소를 Terraform으로 생성하고 이미지를 푸시
- ECS Fargate + ALB 배포 (헬스체크 경로는 `/actuator/health`)
