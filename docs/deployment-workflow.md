# 배포 워크플로우 가이드

GitHub Actions를 활용한 CI/CD 파이프라인 설정 가이드입니다.

## 목차

- [개요](#개요)
- [CI 파이프라인](#ci-파이프라인)
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
│  │ Install │ → │  Build  │ → │ Deploy                   │   │
│  └─────────┘    └─────────┘    └─────────────────────────┘   │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

---

## CI 파이프라인

모든 PR과 push에서 자동으로 코드 품질 검사가 실행됩니다.

### Frontend (Dashboard)

```yaml
jobs:
  lint-and-test:
    steps:
      - npm ci
      - npm run lint        # ESLint
      - npm run type-check  # TypeScript
      - npm run test:run    # Vitest
```

### Backend

```yaml
jobs:
  test:
    steps:
      - bun install --frozen-lockfile
      - bun run typecheck   # TypeScript
      - bun run test:run    # Vitest
```

### CI 흐름

```
PR 생성 / Push
      │
      ▼
┌─────────────┐
│ lint & test │ ─── 실패 시 배포 중단
└─────────────┘
      │ 성공
      ▼
┌─────────────┐
│   deploy    │ ─── push 이벤트에서만 실행
└─────────────┘
```

---

## Frontend 배포 (Vercel)

### 현재 사용 중인 워크플로우

**방식**: GitHub Actions + Vercel CLI

```yaml
# .github/workflows/vercel-deploy.yml
name: Vercel CI/CD (main→production · staging→staging · develop→preview)

on:
  push:
    branches: [main, staging, develop]

jobs:
  deploy:
    runs-on: ubuntu-latest
    concurrency:
      group: deploy-${{ github.ref }}
      cancel-in-progress: true

    env:
      VERCEL_ORG_ID: ${{ secrets.VERCEL_ORG_ID }}
      VERCEL_PROJECT_ID: ${{ secrets.VERCEL_PROJECT_ID }}
      VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node (for CLI only)
        uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "npm"

      - name: Deploy to Vercel
        id: vercel
        run: |
          if [ "${{ github.ref_name }}" = "main" ]; then
            npx vercel@latest pull --yes --environment=production --token="${{ env.VERCEL_TOKEN }}"
            npx vercel@latest build --prod --token="${{ env.VERCEL_TOKEN }}"
            URL=$(npx vercel@latest deploy --prebuilt --prod --yes --token="${{ env.VERCEL_TOKEN }}")
            echo "DEPLOY_ENV=Production" >> "$GITHUB_ENV"
          elif [ "${{ github.ref_name }}" = "staging" ]; then
            npx vercel@latest pull --yes --environment=preview --token="${{ env.VERCEL_TOKEN }}"
            npx vercel@latest build --token="${{ env.VERCEL_TOKEN }}"
            URL=$(npx vercel@latest deploy --prebuilt --yes --token="${{ env.VERCEL_TOKEN }}")
            echo "DEPLOY_ENV=Staging" >> "$GITHUB_ENV"
          else
            npx vercel@latest pull --yes --environment=preview --token="${{ env.VERCEL_TOKEN }}"
            npx vercel@latest build --token="${{ env.VERCEL_TOKEN }}"
            URL=$(npx vercel@latest deploy --prebuilt --yes --token="${{ env.VERCEL_TOKEN }}")
            echo "DEPLOY_ENV=Preview" >> "$GITHUB_ENV"
          fi
          echo "DEPLOY_URL=$URL" >> "$GITHUB_ENV"

      - name: Summary
        if: success()
        run: |
          echo "### ✅ Vercel Deploy"
          echo "- Environment: ${DEPLOY_ENV}"
          echo "- URL: ${DEPLOY_URL}"
```

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

### Frontend (Dashboard)

| Secret | 설명 | 획득 방법 |
|--------|------|-----------|
| `VERCEL_ORG_ID` | Vercel Organization ID | Vercel > Settings > General |
| `VERCEL_PROJECT_ID` | Vercel Project ID | `.vercel/project.json` 또는 Dashboard |
| `VERCEL_TOKEN` | Vercel API Token | Vercel > Settings > Tokens |

### Backend

| 환경 | HOST | USER | KEY |
|------|------|------|-----|
| Development | `DEV_DEPLOY_HOST` | `DEV_DEPLOY_USER` | `DEV_DEPLOY_KEY` |
| Staging | `STAGE_DEPLOY_HOST` | `STAGE_DEPLOY_USER` | `STAGE_DEPLOY_KEY` |
| Production | `PROD_DEPLOY_HOST` | `PROD_DEPLOY_USER` | `PROD_DEPLOY_KEY` |

| Secret | 현재 값 |
|--------|---------|
| `*_DEPLOY_HOST` | `15.165.206.67` |
| `*_DEPLOY_USER` | `ec2-user` |
| `*_DEPLOY_KEY` | SSH 프라이빗 키 (pem 파일 내용) |

### Secrets 설정 방법

1. GitHub Repository > Settings > Secrets and variables > Actions
2. "New repository secret" 클릭
3. Name과 Secret 입력

---

## 배포 체크리스트

### 배포 전

- [ ] 로컬에서 빌드 테스트 완료
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
- [ ] Staging 환경에서 QA 테스트

### Production 배포

- [ ] `staging` → `main` PR 생성
- [ ] 최종 변경 사항 리뷰
- [ ] 팀 승인 획득
- [ ] PR 머지
- [ ] Production 환경 모니터링
- [ ] 롤백 계획 준비

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

## CI/CD 파이프라인 상태

### 테스트 완료 (2026-01-22)

| Repository | 브랜치 | 환경 | 상태 |
|------------|--------|------|------|
| growthmaker-dashboard | `main` | Production | ✅ 성공 |
| growthmaker-dashboard | `staging` | Staging | ✅ 성공 |
| growthmaker-dashboard | `develop` | Preview | ✅ 성공 |
| growthmaker-backend | `main` | Production | ✅ 성공 |
| growthmaker-backend | `staging` | Staging | ✅ 성공 |
| growthmaker-backend | `develop` | Development | ✅ 성공 |

---

## 모니터링

### PM2 명령어

```bash
pm2 status                    # 상태 확인
pm2 logs growthmaker-prod     # 로그 확인
pm2 monit                     # 모니터링 대시보드
```

---

**문서 버전**: 1.4
**최종 수정**: 2026-01-22
