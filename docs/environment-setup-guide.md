# 환경 분리 가이드 (Dev / Staging / Production)

이 문서는 ScaleUp Squad의 모든 프로젝트에서 사용하는 환경 분리 전략을 설명합니다.

## 목차

- [개요](#개요)
- [아키텍처](#아키텍처)
- [환경별 구성](#환경별-구성)
- [환경 변수 설정](#환경-변수-설정)
- [Supabase 환경 분리](#supabase-환경-분리)
- [도메인 구성](#도메인-구성)

---

## 개요

### 환경 정의

| 환경 | 목적 | 사용자 |
|------|------|--------|
| **Development** | 개발 및 테스트 | 개발자 |
| **Staging** | QA 및 배포 전 검증 | 개발자, QA |
| **Production** | 실 서비스 운영 | 최종 사용자 |

### 환경별 브랜치 매핑

```
main (prod)     ← Production 배포
     ↑
staging         ← Staging 배포
     ↑
develop         ← Development 배포
     ↑
feature/*       ← 기능 개발
```

---

## 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                        Frontend                              │
│                        (Vercel)                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │     Dev     │  │   Staging   │  │ Production  │          │
│  │   Preview   │  │   Preview   │  │    Prod     │          │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘          │
└─────────┼────────────────┼────────────────┼─────────────────┘
          │                │                │
          ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────┐
│                        Backend                               │
│                       (AWS EC2)                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │   Dev EC2   │  │ Staging EC2 │  │  Prod EC2   │          │
│  │   :3001     │  │   :3001     │  │   :3001     │          │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘          │
└─────────┼────────────────┼────────────────┼─────────────────┘
          │                │                │
          ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────┐
│                       Database                               │
│                      (Supabase)                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │     Dev     │  │   Staging   │  │ Production  │          │
│  │   Project   │  │   Project   │  │   Project   │          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

---

## 환경별 구성

### Frontend (Vercel)

**단일 프로젝트 + 브랜치별 배포 방식 사용**

| 브랜치 | Vercel 환경 | 도메인 |
|--------|-------------|--------|
| `develop` | Preview | `dev.example.com` |
| `staging` | Preview | `staging.example.com` |
| `main` | Production | `example.com` |

#### vercel.json 설정

```json
{
  "git": {
    "deploymentEnabled": {
      "main": true,
      "staging": true,
      "develop": true
    }
  }
}
```

#### Vercel 환경 변수 설정

Vercel Dashboard > Settings > Environment Variables에서 설정:

| 변수명 | Development | Preview (staging) | Production |
|--------|-------------|-------------------|------------|
| `NEXT_PUBLIC_ENV` | `development` | `staging` | `production` |
| `NEXT_PUBLIC_API_URL` | dev API URL | staging API URL | prod API URL |
| `NEXT_PUBLIC_SUPABASE_URL` | dev Supabase | staging Supabase | prod Supabase |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | dev key | staging key | prod key |

> **참고**: Preview 환경에서 staging 브랜치를 구분하려면 Vercel의 "Git Branch" 조건을 사용하여 환경 변수를 오버라이드합니다.

---

### Backend (AWS EC2)

#### 옵션 1: 환경별 EC2 인스턴스 분리 (권장)

| 환경 | 인스턴스 타입 | 도메인 |
|------|---------------|--------|
| Development | t3.micro | `api-dev.example.com` |
| Staging | t3.small | `api-staging.example.com` |
| Production | t3.medium+ | `api.example.com` |

#### 옵션 2: 단일 EC2 + Docker Compose (비용 절감)

```yaml
# docker-compose.yml
version: '3.8'

services:
  backend-dev:
    build: .
    ports:
      - "3001:3000"
    env_file:
      - .env.development
    restart: unless-stopped

  backend-staging:
    build: .
    ports:
      - "3002:3000"
    env_file:
      - .env.staging
    restart: unless-stopped

  backend-prod:
    build: .
    ports:
      - "3003:3000"
    env_file:
      - .env.production
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf
      - ./nginx/ssl:/etc/nginx/ssl
    depends_on:
      - backend-dev
      - backend-staging
      - backend-prod
    restart: unless-stopped
```

#### Nginx 설정 (옵션 2용)

```nginx
# nginx/nginx.conf
events {
    worker_connections 1024;
}

http {
    upstream backend-dev {
        server backend-dev:3000;
    }

    upstream backend-staging {
        server backend-staging:3000;
    }

    upstream backend-prod {
        server backend-prod:3000;
    }

    server {
        listen 80;
        server_name api-dev.example.com;

        location / {
            proxy_pass http://backend-dev;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_cache_bypass $http_upgrade;
        }
    }

    server {
        listen 80;
        server_name api-staging.example.com;

        location / {
            proxy_pass http://backend-staging;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_cache_bypass $http_upgrade;
        }
    }

    server {
        listen 80;
        server_name api.example.com;

        location / {
            proxy_pass http://backend-prod;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_cache_bypass $http_upgrade;
        }
    }
}
```

#### PM2 프로세스 관리 (EC2 분리 시)

```bash
# ecosystem.config.js
module.exports = {
  apps: [{
    name: 'growthmaker-api',
    script: 'dist/main.js',
    instances: 'max',
    exec_mode: 'cluster',
    env_development: {
      NODE_ENV: 'development'
    },
    env_staging: {
      NODE_ENV: 'staging'
    },
    env_production: {
      NODE_ENV: 'production'
    }
  }]
};
```

```bash
# 환경별 실행
pm2 start ecosystem.config.js --env development
pm2 start ecosystem.config.js --env staging
pm2 start ecosystem.config.js --env production
```

---

## 환경 변수 설정

### Frontend (.env 파일 구조)

```
growthmaker-dashboard/
├── .env.local              # 로컬 개발용 (gitignore)
├── .env.development        # dev 환경 기본값
├── .env.example            # 환경 변수 템플릿 (git에 포함)
```

#### .env.example (템플릿)

```bash
# Environment
NEXT_PUBLIC_ENV=development

# API
NEXT_PUBLIC_API_URL=https://api-dev.example.com

# Supabase
NEXT_PUBLIC_SUPABASE_URL=https://xxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key

# Optional
NEXT_PUBLIC_SENTRY_DSN=
```

#### 환경별 설정 예시

```bash
# .env.development
NEXT_PUBLIC_ENV=development
NEXT_PUBLIC_API_URL=https://api-dev.growthmaker.com
NEXT_PUBLIC_SUPABASE_URL=https://xxx-dev.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=dev_anon_key

# Vercel에서 staging 환경 변수 (Dashboard에서 설정)
NEXT_PUBLIC_ENV=staging
NEXT_PUBLIC_API_URL=https://api-staging.growthmaker.com
NEXT_PUBLIC_SUPABASE_URL=https://xxx-staging.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=staging_anon_key

# Vercel에서 production 환경 변수 (Dashboard에서 설정)
NEXT_PUBLIC_ENV=production
NEXT_PUBLIC_API_URL=https://api.growthmaker.com
NEXT_PUBLIC_SUPABASE_URL=https://xxx-prod.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=prod_anon_key
```

### Backend (.env 파일 구조)

```
growthmaker-backend/
├── .env                    # 로컬 개발용 (gitignore)
├── .env.development        # dev 환경
├── .env.staging            # staging 환경
├── .env.production         # production 환경
├── .env.example            # 템플릿
```

#### .env.example (Backend)

```bash
# Server
NODE_ENV=development
PORT=3000

# Supabase
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_SERVICE_KEY=your_service_key

# CORS
CORS_ORIGIN=https://dev.example.com

# Optional
SENTRY_DSN=
LOG_LEVEL=debug
```

---

## Supabase 환경 분리

### 프로젝트 구성

| 환경 | 프로젝트 이름 | 용도 |
|------|---------------|------|
| Development | `growthmaker-dev` | 개발/테스트 데이터 |
| Staging | `growthmaker-staging` | QA 테스트 데이터 |
| Production | `growthmaker-prod` | 실 서비스 데이터 |

### 마이그레이션 적용 순서

```bash
# 1. Development에 먼저 적용
supabase db push --project-ref <dev-project-ref>

# 2. 테스트 후 Staging에 적용
supabase db push --project-ref <staging-project-ref>

# 3. 최종 검증 후 Production에 적용 (신중하게!)
supabase db push --project-ref <prod-project-ref>
```

### 타입 생성

```bash
# 각 환경별로 타입 생성 (보통 prod 기준으로 생성)
npx supabase gen types typescript --project-id <project-ref> > src/types/database.types.ts
```

---

## 도메인 구성

### 예시 도메인 구조

| 서비스 | Development | Staging | Production |
|--------|-------------|---------|------------|
| Frontend | dev.growthmaker.com | staging.growthmaker.com | growthmaker.com |
| API | api-dev.growthmaker.com | api-staging.growthmaker.com | api.growthmaker.com |

### DNS 설정

```
# Vercel (Frontend)
dev.growthmaker.com      → CNAME cname.vercel-dns.com
staging.growthmaker.com  → CNAME cname.vercel-dns.com
growthmaker.com          → A 76.76.19.19

# AWS EC2 (Backend)
api-dev.growthmaker.com      → A <dev-ec2-ip>
api-staging.growthmaker.com  → A <staging-ec2-ip>
api.growthmaker.com          → A <prod-ec2-ip>
```

---

## 다음 단계

- [브랜치 전략](./branching-strategy.md) - Git 브랜치 관리 방법
- [배포 워크플로우](./deployment-workflow.md) - CI/CD 파이프라인 설정

---

**문서 버전**: 1.0
**최종 수정**: 2025-01-22
