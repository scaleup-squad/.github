# 배포 워크플로우 가이드

GitHub Actions를 활용한 CI/CD 파이프라인 설정 가이드입니다.

## 목차

- [개요](#개요)
- [Frontend 배포 (Vercel)](#frontend-배포-vercel)
- [Backend 배포 (AWS EC2)](#backend-배포-aws-ec2)
- [GitHub Secrets 설정](#github-secrets-설정)
- [배포 체크리스트](#배포-체크리스트)

---

## 개요

### 배포 트리거

| 브랜치 | 이벤트 | 배포 환경 |
|--------|--------|-----------|
| `develop` | push | Development |
| `staging` | push | Staging |
| `main` | push | Production |

### 파이프라인 흐름

```
┌──────────────────────────────────────────────────────────────┐
│                      GitHub Actions                           │
│                                                               │
│  push to branch                                               │
│       │                                                       │
│       ▼                                                       │
│  ┌─────────┐    ┌─────────┐    ┌─────────────────────────┐   │
│  │ Install │ → │  Build  │ → │ Deploy (SSH to EC2)     │   │
│  └─────────┘    └─────────┘    └─────────────────────────┘   │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

---

## Frontend 배포 (Vercel)

### Vercel 자동 배포 (현재 사용 중)

Vercel은 GitHub 연동 시 자동으로 브랜치별 배포를 수행합니다.

| 브랜치 | 배포 환경 | 도메인 |
|--------|-----------|--------|
| `develop` | Preview | Vercel Preview URL |
| `staging` | Preview | Vercel Preview URL |
| `main` | Production | `app.growthmaker.kr` |

**설정 방법:**

1. Vercel Dashboard에서 프로젝트 Import
2. GitHub 레포지토리 연결
3. 환경 변수 설정 (Settings > Environment Variables)
4. 브랜치별 도메인 설정 (Settings > Domains)

---

## Backend 배포 (AWS EC2)

### 현재 사용 중인 워크플로우

**런타임**: Bun
**배포 방식**: EC2에서 배포 스크립트 실행

```yaml
# .github/workflows/deploy.yml
name: Deploy growthmaker-backend (dev/stage/prod)

on:
  push:
    branches:
      - develop
      - staging
      - main

concurrency:
  group: growthmaker-backend-${{ github.ref }}
  cancel-in-progress: true

env:
  APP_NAME: growthmaker-backend

jobs:
  deploy-dev:
    if: github.ref == 'refs/heads/develop'
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Bun
        uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest

      - name: Install dependencies
        run: bun install --frozen-lockfile

      - name: Build
        run: bun run build

      - name: Deploy to DEV
        uses: appleboy/ssh-action@v1.0.0
        with:
          host: ${{ secrets.DEV_DEPLOY_HOST }}
          username: ${{ secrets.DEV_DEPLOY_USER }}
          key: ${{ secrets.DEV_DEPLOY_KEY }}
          script: |
            ~/deploy-growthmaker-backend.sh dev

  deploy-stage:
    if: github.ref == 'refs/heads/staging'
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Bun
        uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest

      - name: Install dependencies
        run: bun install --frozen-lockfile

      - name: Build
        run: bun run build

      - name: Deploy to STAGE
        uses: appleboy/ssh-action@v1.0.0
        with:
          host: ${{ secrets.STAGE_DEPLOY_HOST }}
          username: ${{ secrets.STAGE_DEPLOY_USER }}
          key: ${{ secrets.STAGE_DEPLOY_KEY }}
          script: |
            ~/deploy-growthmaker-backend.sh stage

  deploy-prod:
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Bun
        uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest

      - name: Install dependencies
        run: bun install --frozen-lockfile

      - name: Build
        run: bun run build

      - name: Deploy to PROD
        uses: appleboy/ssh-action@v1.0.0
        with:
          host: ${{ secrets.PROD_DEPLOY_HOST }}
          username: ${{ secrets.PROD_DEPLOY_USER }}
          key: ${{ secrets.PROD_DEPLOY_KEY }}
          script: |
            ~/deploy-growthmaker-backend.sh prod
```

### EC2 배포 스크립트

EC2에 `~/deploy-growthmaker-backend.sh` 스크립트가 설치되어 있어야 합니다.

```bash
#!/bin/bash
# ~/deploy-growthmaker-backend.sh

ENV=$1  # dev, stage, prod

cd /var/www/growthmaker-backend

# Git pull
git fetch origin
if [ "$ENV" == "dev" ]; then
  git checkout develop
  git pull origin develop
elif [ "$ENV" == "stage" ]; then
  git checkout staging
  git pull origin staging
else
  git checkout main
  git pull origin main
fi

# Install & Build
bun install --frozen-lockfile
bun run build

# Restart PM2
pm2 restart growthmaker-$ENV --update-env

echo "✅ Deployed to $ENV"
```

---

## GitHub Secrets 설정

### Frontend (Vercel) - 현재 미사용

Vercel 자동 배포를 사용 중이므로 별도 Secrets 불필요

### Backend (AWS EC2)

| 환경 | HOST | USER | KEY |
|------|------|------|-----|
| Development | `DEV_DEPLOY_HOST` | `DEV_DEPLOY_USER` | `DEV_DEPLOY_KEY` |
| Staging | `STAGE_DEPLOY_HOST` | `STAGE_DEPLOY_USER` | `STAGE_DEPLOY_KEY` |
| Production | `PROD_DEPLOY_HOST` | `PROD_DEPLOY_USER` | `PROD_DEPLOY_KEY` |

| Secret | 설명 | 현재 값 |
|--------|------|---------|
| `*_DEPLOY_HOST` | EC2 IP | `15.165.206.67` |
| `*_DEPLOY_USER` | SSH 사용자명 | `ec2-user` |
| `*_DEPLOY_KEY` | SSH 프라이빗 키 (pem 파일 내용) | `-----BEGIN RSA...` |

### Secrets 설정 방법

1. GitHub Repository > Settings > Secrets and variables > Actions
2. "New repository secret" 클릭
3. Name과 Secret 입력

---

## 배포 체크리스트

### 배포 전

- [ ] 로컬에서 빌드 테스트 완료 (`bun run build`)
- [ ] 테스트 통과 확인
- [ ] 환경 변수 설정 확인
- [ ] 마이그레이션 필요 여부 확인

### Development 배포

- [ ] `feature/*` → `develop` PR 머지
- [ ] GitHub Actions 성공 확인
- [ ] Dev 환경에서 기능 테스트

### Staging 배포

- [ ] `develop` → `staging` PR 생성
- [ ] 변경 사항 리뷰
- [ ] PR 머지
- [ ] Staging 환경에서 QA 테스트 (`api.growthmaker.kr/stage`)

### Production 배포

- [ ] `staging` → `main` PR 생성
- [ ] 최종 변경 사항 리뷰
- [ ] 팀 승인 획득
- [ ] PR 머지
- [ ] Production 환경 모니터링 (`api.growthmaker.kr`)
- [ ] 롤백 계획 준비

### 배포 후

- [ ] 헬스체크 확인
- [ ] 주요 기능 스모크 테스트
- [ ] 에러 로그 모니터링
- [ ] 성능 지표 확인

---

## 롤백 절차

### Vercel (Frontend)

```bash
# Vercel Dashboard에서 이전 배포로 롤백
# Deployments > 이전 배포 선택 > ... > Promote to Production

# 또는 CLI
vercel rollback
```

### EC2 (Backend)

```bash
# SSH로 EC2 접속
ssh -i key.pem ec2-user@15.165.206.67

# 이전 커밋으로 롤백
cd /var/www/growthmaker-backend
git log --oneline -10  # 롤백할 커밋 확인
git checkout <commit-hash>

# 재빌드 및 재시작
bun install --frozen-lockfile
bun run build
pm2 restart growthmaker-prod
```

---

## 모니터링

### 권장 도구

| 용도 | 도구 |
|------|------|
| 에러 추적 | Sentry |
| 로그 관리 | AWS CloudWatch |
| 성능 모니터링 | Vercel Analytics, PM2 |
| 알림 | Slack |

### PM2 모니터링 명령어

```bash
# 상태 확인
pm2 status

# 로그 확인
pm2 logs growthmaker-prod

# 모니터링 대시보드
pm2 monit
```

---

**문서 버전**: 1.1
**최종 수정**: 2025-01-22
