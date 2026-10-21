# ---- Build stage: compile the Spring Boot jar with the Gradle wrapper ----
FROM eclipse-temurin:17-jdk AS build

WORKDIR /workspace

# Copy build scripts first so the dependency layer is cached until they change.
COPY gradlew settings.gradle build.gradle ./
COPY gradle gradle
RUN ./gradlew dependencies --no-daemon --quiet > /dev/null

COPY src src
RUN ./gradlew bootJar --no-daemon

# ---- Runtime stage: JRE + jar only ----
FROM eclipse-temurin:17-jre

WORKDIR /app
COPY --from=build /workspace/build/libs/app.jar app.jar

RUN useradd --system --uid 1001 spring
USER spring

# Cloud Run sets PORT (default 8080); application.properties reads it.
EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "/app/app.jar"]
