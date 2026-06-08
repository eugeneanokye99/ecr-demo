# Architecture

## High-Level Flow

```mermaid
flowchart TD
    Dev([Developer]) -->|git push| GH[GitHub Repository]

    GH -->|triggers| GA[GitHub Actions Workflow]

    subgraph CI ["CI/CD Pipeline (ubuntu-latest runner)"]
        GA --> S1[Checkout Code]
        S1 --> S2[Configure AWS Credentials\nvia OIDC]
        S2 --> S3[Login to ECR]
        S3 --> S4[mvn clean package]
        S4 --> S5[docker build]
        S5 --> S6[docker tag]
        S6 --> S7[docker push]
    end

    subgraph AWS ["AWS Cloud"]
        subgraph IAM ["IAM"]
            OIDC[OIDC Identity Provider\ntoken.actions.githubusercontent.com]
            ROLE[IAM Role\nGitHub-ECR-Push-Role]
            OIDC -->|validates token| ROLE
        end

        subgraph ECR ["Amazon ECR"]
            REPO[Private Repository\neugene_ecr-demo\nScan on Push enabled]
        end
    end

    S2 -->|request OIDC token| OIDC
    ROLE -->|temporary credentials| S2
    S7 -->|authenticated push| REPO

    style CI fill:#f0f4ff,stroke:#4a6fa5
    style AWS fill:#fff8f0,stroke:#e8820c
    style IAM fill:#fff3e0,stroke:#f59e0b
    style ECR fill:#e8f5e9,stroke:#4caf50
```

---

## Authentication Flow (OIDC)

```mermaid
sequenceDiagram
    participant R as GitHub Runner
    participant G as GitHub OIDC Endpoint
    participant S as AWS STS
    participant I as IAM (OIDC Provider)
    participant E as Amazon ECR

    R->>G: Request JWT (id-token: write)
    G-->>R: Signed JWT<br/>(sub: repo:org/repo:ref:refs/heads/main)

    R->>S: AssumeRoleWithWebIdentity (JWT)
    S->>I: Validate JWT signature & claims
    I-->>S: Claims verified
    S-->>R: Temporary credentials<br/>(AccessKey + SecretKey + SessionToken)

    R->>E: GetAuthorizationToken
    E-->>R: Docker login token (12 hrs)
    R->>E: docker push image
    E-->>R: 200 OK — image stored
```

---

## AWS Infrastructure

```
AWS Account
├── IAM
│   ├── OIDC Provider: token.actions.githubusercontent.com
│   │   └── Audience: sts.amazonaws.com
│   └── Role: GitHub-ECR-Push-Role
│       ├── Trust Policy: repo:YOUR_ORG/ecr-demo:*
│       └── Inline Policy: ECRLeastPrivilege
│           ├── ecr:GetAuthorizationToken   (resource: *)
│           ├── ecr:BatchCheckLayerAvailability
│           ├── ecr:CompleteLayerUpload
│           ├── ecr:InitiateLayerUpload
│           ├── ecr:PutImage
│           ├── ecr:UploadLayerPart
│           └── ecr:BatchGetImage           (resource: repository ARN only)
└── ECR
    └── Repository: eugene_ecr-demo (private)
        ├── Scan on Push: enabled
        ├── Encryption: AES256
        └── Lifecycle: keep last 10 images
```

---

## Docker Image Layers

```
eclipse-temurin:17-jre-alpine   ← base (JRE only, ~85 MB)
└── WORKDIR /app
    └── COPY target/*.jar app.jar
        └── RUN addgroup/adduser spring   ← non-root user
            └── USER spring
                └── EXPOSE 8080
                    └── ENTRYPOINT ["java","-jar","app.jar"]
```
