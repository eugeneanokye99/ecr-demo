FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

COPY target/*.jar app.jar

RUN addgroup -S spring && adduser -S spring -G spring

USER spring

EXPOSE 8080

ENTRYPOINT ["java","-jar","app.jar"]
