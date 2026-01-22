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

### 현재 구성

```
┌─────────────────────────────────────────────────────────────┐
│                        Frontend                              │
│                        (Vercel)                              │
│  ┌─────────────────────────────────┐  ┌─────────────┐       │
│  │  Preview (develop/staging)      │  │ Production  │       │
│  │  app.growthmaker.kr (Preview)   │  │   (main)    │       │
│  └──────────────┬──────────────────┘  └──────┬──────┘       │
└─────────────────┼────────────────────────────┼──────────────┘
                  │                            │
                  ▼                            ▼
┌─────────────────────────────────────────────────────────────┐
│                        Backend                               │
│                       (AWS EC2)                              │
│  ┌─────────────────────────────────┐  ┌─────────────┐       │
│  │  api.growthmaker.kr/stage       │  │   (prod)    │       │
│  │  (Staging API)                  │  │ api.grow... │       │
│  └──────────────┬──────────────────┘  └──────┬──────┘       │
└─────────────────┼────────────────────────────┼──────────────┘
                  │                            │
                  ▼                            ▼
┌─────────────────────────────────────────────────────────────┐
│                       Database                               │
│                      (Supabase)                              │
│  ┌─────────────────────────────────────────────────┐        │
│  │  sssfkmjaoqkltwoaipbc.supabase.co               │        │
│  │  (단일 프로젝트 - 모든 환경 공유)                  │        │
│  └─────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

### 향후 목표 구성 (환경 완전 분리)

```
Frontend (Vercel)     Backend (AWS EC2)      Database (Supabase)
─────────────────     ─────────────────      ───────────────────
develop (Preview)  →  api-dev.xxx.kr      →  growthmaker-dev
staging (Preview)  →  api-staging.xxx.kr  →  growthmaker-staging
main (Production)  →  api.xxx.kr          →  growthmaker-prod
```

---

## 환경별 구성

### Frontend (Vercel)

**단일 프로젝트 + 브랜치별 배포 방식 사용**

| 브랜치 | Vercel 환경 | 비고 |
|--------|-------------|------|
| `develop` | Preview | 개발 테스트 |
| `staging` | Preview | QA 테스트 |
| `main` | Production | 실 서비스 |

#### Vercel 환경 변수 현황

| 변수명 | Production | Preview | 비고 |
|--------|------------|---------|------|
| `NEXT_PUBLIC_API_URL` | `https://api.growthmaker.kr` | `https://api.growthmaker.kr/stage` | 환경별 분리 |
| `NEXT_PUBLIC_SUPABASE_URL` | `https://sssfkmjaoqkltwoaipbc.supabase.co` | 동일 | 단일 프로젝트 |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | All Environments | - | 단일 프로젝트 |
| `SUPABASE_SERVICE_ROLE_KEY` | All Environments | - | 단일 프로젝트 |
| `NEXT_PUBLIC_BASE_URL` | `https://app.growthmaker.kr` | 동일 | - |
| `SLACK_WEBHOOK_URL` | All Environments | - | 알림용 |

---

### Backend (AWS EC2)

#### 현재 구성: 경로 기반 분리

| 환경 | API Endpoint |
|------|--------------|
| Staging | `https://api.growthmaker.kr/stage` |
| Production | `https://api.growthmaker.kr` |

#### 향후 구성: 환경별 EC2 인스턴스 분리 (권장)

| 환경 | 인스턴스 타입 | 도메인 |
|------|---------------|--------|
| Development | t3.micro | `api-dev.growthmaker.kr` |
| Staging | t3.small | `api-staging.growthmaker.kr` |
| Production | t3.medium+ | `api.growthmaker.kr` |

#### PM2 프로세스 관리

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
├── .env.example            # 환경 변수 템플릿 (git에 포함)
```

#### .env.example (템플릿)

```bash
# App
NEXT_PUBLIC_BASE_URL=https://app.growthmaker.kr

# API
NEXT_PUBLIC_API_URL=https://api.growthmaker.kr

# Supabase
NEXT_PUBLIC_SUPABASE_URL=https://sssfkmjaoqkltwoaipbc.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key

# Notifications
SLACK_WEBHOOK_URL=your_slack_webhook_url
```

### Backend (.env 파일 구조)

```
growthmaker-backend/
├── .env                    # 로컬 개발용 (gitignore)
├── .env.example            # 템플릿
```

#### .env.example (Backend)

```bash
# Server
NODE_ENV=development
PORT=3000

# Supabase
SUPABASE_URL=https://sssfkmjaoqkltwoaipbc.supabase.co
SUPABASE_SERVICE_KEY=your_service_key

# CORS
CORS_ORIGIN=https://app.growthmaker.kr

# Optional
SLACK_WEBHOOK_URL=
LOG_LEVEL=debug
```

---

## Supabase 환경 분리

### 현재 상태: 단일 프로젝트

| 환경 | 프로젝트 | 용도 |
|------|----------|------|
| 모든 환경 | `sssfkmjaoqkltwoaipbc` | 개발/스테이징/프로덕션 공유 |

> ⚠️ **주의**: 현재 모든 환경에서 동일한 Supabase 프로젝트를 사용 중입니다.
> 스테이징에서의 테스트 데이터가 프로덕션에 영향을 줄 수 있습니다.

### 향후 목표: 환경별 분리

| 환경 | 프로젝트 이름 | 용도 |
|------|---------------|------|
| Development | `growthmaker-dev` | 개발/테스트 데이터 |
| Staging | `growthmaker-staging` | QA 테스트 데이터 |
| Production | `growthmaker-prod` | 실 서비스 데이터 |

### 마이그레이션 적용 순서 (환경 분리 시)

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
# 타입 생성 (현재 단일 프로젝트)
npx supabase gen types typescript --project-id sssfkmjaoqkltwoaipbc > src/types/database.types.ts
```

---

## 도메인 구성

### 현재 도메인 구조

| 서비스 | Staging | Production |
|--------|---------|------------|
| Frontend | Preview URL (Vercel) | `app.growthmaker.kr` |
| API | `api.growthmaker.kr/stage` | `api.growthmaker.kr` |

### 향후 도메인 구조 (권장)

| 서비스 | Development | Staging | Production |
|--------|-------------|---------|------------|
| Frontend | `dev.growthmaker.kr` | `staging.growthmaker.kr` | `app.growthmaker.kr` |
| API | `api-dev.growthmaker.kr` | `api-staging.growthmaker.kr` | `api.growthmaker.kr` |

---

## 다음 단계

- [브랜치 전략](./branching-strategy.md) - Git 브랜치 관리 방법
- [배포 워크플로우](./deployment-workflow.md) - CI/CD 파이프라인 설정

---

**문서 버전**: 1.1
**최종 수정**: 2025-01-22
