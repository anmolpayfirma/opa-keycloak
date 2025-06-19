# Multi-stage Dockerfile for Java Spring Boot application
FROM openjdk:17-jdk-alpine AS builder

# Install bash and other utilities needed by Maven wrapper
RUN apk add --no-cache bash curl

# Set working directory
WORKDIR /app

# Copy Maven wrapper and pom.xml
COPY mvnw .
COPY mvnw.cmd .
COPY .mvn .mvn
COPY pom.xml .

# Make mvnw executable and verify it
RUN chmod +x ./mvnw && ls -la ./mvnw

# Test basic Java functionality
RUN java -version

# Download dependencies (this might fail, so let's see)
RUN ./mvnw dependency:go-offline -B || echo "Dependency download failed, continuing..."

# Copy source code
COPY src src

# Build the application
RUN ./mvnw clean package -DskipTests -X || echo "Build failed, checking what we have..." && ls -la target/ || echo "No target directory"

# Runtime stage - using the same JDK image for now since JRE-only isn't available
FROM openjdk:17-jdk-alpine

# Set working directory
WORKDIR /app

# Create non-root user for security
RUN addgroup -g 1001 -S merchantuser && \
    adduser -S merchantuser -u 1001 -G merchantuser

# Copy the built jar from builder stage - try to find it first
COPY --from=builder /app/target/*.jar app.jar

# Change ownership to non-root user
RUN chown merchantuser:merchantuser app.jar

# Switch to non-root user
USER merchantuser

# Expose port
EXPOSE 8080

# Run the application
CMD ["java", "-jar", "app.jar"] 