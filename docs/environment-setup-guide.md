# 환경 분리 가이드 (Dev / Staging / Production)

이 문서는 ScaleUp Squad의 모든 프로젝트에서 사용하는 환경 분리 전략을 설명합니다.

## 목차

- [개요](#개요)
- [아키텍처](#아키텍처)
- [환경별 구성](#환경별-구성)
- [환경 변수 설정](#환경-변수-설정)
- [Supabase 설정](#supabase-설정)
- [도메인 구성](#도메인-구성)

---

## 개요

### 환경 정의

| 환경 | 목적 | 사용자 |
|------|------|--------|
| **Development** | 개발 및 테스트 | 개발자 |
| **Staging** | QA 및 배포 전 검증 | 개발자, QA |
| **Production** | 실 서비스 운영 | 최종 사용자 |

### 브랜치 전략

```
main (prod)     ← Production 배포
     ↑
staging         ← Staging 배포
     ↑
develop         ← Development 배포
     ↑
feature/*       ← 기능 개발
```

| Repository | 브랜치 | 배포 환경 |
|------------|--------|-----------|
| Dashboard | `main` | Production |
| Dashboard | `staging` | Staging |
| Dashboard | `develop` | Development (Preview) |
| Backend | `main` | Production |
| Backend | `staging` | Staging |
| Backend | `develop` | Development |

---

## 아키텍처

### 현재 구성

```
┌─────────────────────────────────────────────────────────────┐
│                        Frontend                              │
│                        (Vercel)                              │
│  ┌─────────────────────────────────┐  ┌─────────────┐       │
│  │  Preview (develop/staging)      │  │ Production  │       │
│  │                                 │  │   (main)    │       │
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

---

## 환경별 구성

### Frontend (Vercel)

**GitHub Actions + Vercel CLI 배포 방식 사용**

| 브랜치 | Vercel 환경 | 비고 |
|--------|-------------|------|
| `develop` | Preview | 개발 테스트 |
| `staging` | Preview | QA 테스트 |
| `main` | Production | 실 서비스 (`app.growthmaker.kr`) |

#### GitHub Secrets (Dashboard)

| Secret | 설명 |
|--------|------|
| `VERCEL_ORG_ID` | Vercel Organization ID |
| `VERCEL_PROJECT_ID` | Vercel Project ID |
| `VERCEL_TOKEN` | Vercel API Token |

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

**Bun 런타임 + EC2 배포 스크립트 방식 사용**

#### 현재 구성: 단일 EC2 + 경로 기반 분리

| 환경 | API Endpoint | EC2 |
|------|--------------|-----|
| Development | `https://api.growthmaker.kr/dev` | 15.165.206.67 |
| Staging | `https://api.growthmaker.kr/stage` | 15.165.206.67 |
| Production | `https://api.growthmaker.kr` | 15.165.206.67 |

#### GitHub Secrets (Backend)

| 환경 | HOST | USER | KEY |
|------|------|------|-----|
| Development | `DEV_DEPLOY_HOST` | `DEV_DEPLOY_USER` | `DEV_DEPLOY_KEY` |
| Staging | `STAGE_DEPLOY_HOST` | `STAGE_DEPLOY_USER` | `STAGE_DEPLOY_KEY` |
| Production | `PROD_DEPLOY_HOST` | `PROD_DEPLOY_USER` | `PROD_DEPLOY_KEY` |

| Secret | 현재 값 |
|--------|---------|
| `*_DEPLOY_HOST` | `15.165.206.67` |
| `*_DEPLOY_USER` | `ec2-user` |
| `*_DEPLOY_KEY` | SSH 프라이빗 키 (pem) |

---

## 환경 변수 설정

### Frontend (.env 파일 구조)

```
growthmaker-dashboard/
├── .env.local              # 로컬 개발용 (gitignore)
├── .env.example            # 환경 변수 템플릿 (git에 포함)
```

#### .env.example

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

---

## Supabase 설정

### 현재 상태: 단일 프로젝트

| 환경 | 프로젝트 | URL |
|------|----------|-----|
| 모든 환경 | `sssfkmjaoqkltwoaipbc` | `https://sssfkmjaoqkltwoaipbc.supabase.co` |

> ⚠️ **주의**: 현재 모든 환경에서 동일한 Supabase 프로젝트를 사용 중입니다.

### 타입 생성

```bash
npx supabase gen types typescript --project-id sssfkmjaoqkltwoaipbc > src/types/database.types.ts
```

---

## 도메인 구성

### 현재 도메인 구조

| 서비스 | Staging | Production |
|--------|---------|------------|
| Frontend | Vercel Preview URL | `app.growthmaker.kr` |
| API | `api.growthmaker.kr/stage` | `api.growthmaker.kr` |

---

## 다음 단계

- [브랜치 전략](./branching-strategy.md) - Git 브랜치 관리 방법
- [배포 워크플로우](./deployment-workflow.md) - CI/CD 파이프라인 설정

---

**문서 버전**: 1.3
**최종 수정**: 2026-01-22
