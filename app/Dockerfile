# ---------- 1단계: 빌드 (Gradle + JDK) ----------
FROM gradle:9-jdk21 AS build
WORKDIR /workspace

# 의존성 다운로드를 캐시하려고 빌드 설정 파일을 먼저 복사한다.
COPY settings.gradle build.gradle ./
RUN gradle dependencies --no-daemon > /dev/null 2>&1 || true

COPY src ./src
RUN gradle bootJar --no-daemon -x test

# ---------- 2단계: 실행 (JRE만 포함해 이미지를 작게 유지) ----------
# Alpine 기반: Ubuntu 기반(583MB)보다 작고, OS 패키지 취약점이 가장 적었다.
# (Ubuntu/Alpine/Distroless를 Trivy로 비교한 결과는 docs/03-app-docker.md 참고)
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# root가 아닌 일반 사용자로 실행해 컨테이너가 뚫려도 피해를 줄인다.
RUN addgroup -S appuser && adduser -S -G appuser appuser
USER appuser

COPY --from=build /workspace/build/libs/*.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
