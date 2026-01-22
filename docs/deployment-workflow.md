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
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐   │
│  │  Lint   │ → │  Test   │ → │  Build  │ → │ Deploy  │   │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘   │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

---

## Frontend 배포 (Vercel)

### 방법 1: Vercel 자동 배포 (권장)

Vercel은 GitHub 연동 시 자동으로 브랜치별 배포를 수행합니다.

**설정 방법:**

1. Vercel Dashboard에서 프로젝트 Import
2. GitHub 레포지토리 연결
3. 환경 변수 설정 (Settings > Environment Variables)
4. 브랜치별 도메인 설정 (Settings > Domains)

### 방법 2: GitHub Actions로 배포

더 세밀한 제어가 필요한 경우:

```yaml
# .github/workflows/deploy-frontend.yml
name: Deploy Frontend

on:
  push:
    branches: [develop, staging, main]

jobs:
  lint-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Run lint
        run: npm run lint

      - name: Run type check
        run: npm run type-check

      - name: Run tests
        run: npm test --passWithNoTests

  deploy:
    needs: lint-and-test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Deploy to Vercel
        uses: amondnet/vercel-action@v25
        with:
          vercel-token: ${{ secrets.VERCEL_TOKEN }}
          vercel-org-id: ${{ secrets.VERCEL_ORG_ID }}
          vercel-project-id: ${{ secrets.VERCEL_PROJECT_ID }}
          vercel-args: ${{ github.ref == 'refs/heads/main' && '--prod' || '' }}
```

---

## Backend 배포 (AWS EC2)

### GitHub Actions Workflow

```yaml
# .github/workflows/deploy-backend.yml
name: Deploy Backend

on:
  push:
    branches: [develop, staging, main]

env:
  NODE_VERSION: '20'

jobs:
  lint-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Run lint
        run: npm run lint

      - name: Run tests
        run: npm test --passWithNoTests

  deploy:
    needs: lint-and-test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set deployment environment
        id: env
        run: |
          if [ "${{ github.ref }}" == "refs/heads/main" ]; then
            echo "environment=production" >> $GITHUB_OUTPUT
            echo "host=${{ secrets.EC2_HOST_PROD }}" >> $GITHUB_OUTPUT
          elif [ "${{ github.ref }}" == "refs/heads/staging" ]; then
            echo "environment=staging" >> $GITHUB_OUTPUT
            echo "host=${{ secrets.EC2_HOST_STAGING }}" >> $GITHUB_OUTPUT
          else
            echo "environment=development" >> $GITHUB_OUTPUT
            echo "host=${{ secrets.EC2_HOST_DEV }}" >> $GITHUB_OUTPUT
          fi

      - name: Deploy to EC2
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ steps.env.outputs.host }}
          username: ${{ secrets.EC2_USERNAME }}
          key: ${{ secrets.EC2_SSH_KEY }}
          script: |
            cd /var/www/growthmaker-backend

            # Git pull
            git fetch origin
            git checkout ${{ github.ref_name }}
            git pull origin ${{ github.ref_name }}

            # Install dependencies
            npm ci --production

            # Build
            npm run build

            # Restart PM2
            pm2 restart growthmaker-${{ steps.env.outputs.environment }} --update-env

            # Health check
            sleep 5
            curl -f http://localhost:3000/health || exit 1

      - name: Notify on failure
        if: failure()
        uses: 8398a7/action-slack@v3
        with:
          status: failure
          text: '배포 실패: ${{ steps.env.outputs.environment }}'
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

### EC2 초기 설정 스크립트

```bash
#!/bin/bash
# setup-ec2.sh - EC2 초기 설정

# Node.js 설치 (nvm 사용)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc
nvm install 20
nvm use 20

# PM2 설치
npm install -g pm2

# 프로젝트 클론
cd /var/www
git clone git@github.com:scaleup-squad/growthmaker-backend.git
cd growthmaker-backend

# 환경 변수 설정
cp .env.example .env
# .env 파일 편집

# 의존성 설치 및 빌드
npm ci
npm run build

# PM2로 시작
pm2 start ecosystem.config.js --env production
pm2 save
pm2 startup
```

---

## GitHub Secrets 설정

### Frontend (Vercel)

| Secret 이름 | 설명 | 획득 방법 |
|-------------|------|-----------|
| `VERCEL_TOKEN` | Vercel API 토큰 | Vercel > Settings > Tokens |
| `VERCEL_ORG_ID` | Vercel 팀 ID | Vercel > Settings > General |
| `VERCEL_PROJECT_ID` | 프로젝트 ID | .vercel/project.json 또는 Dashboard |

### Backend (AWS EC2)

| 환경 | HOST | USER | KEY |
|------|------|------|-----|
| Development | `DEV_DEPLOY_HOST` | `DEV_DEPLOY_USER` | `DEV_DEPLOY_KEY` |
| Staging | `STAGE_DEPLOY_HOST` | `STAGE_DEPLOY_USER` | `STAGE_DEPLOY_KEY` |
| Production | `PROD_DEPLOY_HOST` | `PROD_DEPLOY_USER` | `PROD_DEPLOY_KEY` |

| Secret | 설명 | 예시 |
|--------|------|------|
| `*_DEPLOY_HOST` | EC2 IP 또는 도메인 | `15.165.206.67` |
| `*_DEPLOY_USER` | SSH 사용자명 | `ec2-user` |
| `*_DEPLOY_KEY` | SSH 프라이빗 키 (pem 파일 내용) | `-----BEGIN RSA...` |

### 공통

| Secret 이름 | 설명 |
|-------------|------|
| `SLACK_WEBHOOK_URL` | Slack 알림용 Webhook URL |

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
ssh -i key.pem ubuntu@api.example.com

# 이전 커밋으로 롤백
cd /var/www/growthmaker-backend
git log --oneline -10  # 롤백할 커밋 확인
git checkout <commit-hash>

# 재빌드 및 재시작
npm ci
npm run build
pm2 restart growthmaker-production
```

---

## 모니터링

### 권장 도구

| 용도 | 도구 |
|------|------|
| 에러 추적 | Sentry |
| 로그 관리 | AWS CloudWatch |
| 성능 모니터링 | Vercel Analytics, PM2 |
| 알림 | Slack, Discord |

### PM2 모니터링 명령어

```bash
# 상태 확인
pm2 status

# 로그 확인
pm2 logs growthmaker-production

# 모니터링 대시보드
pm2 monit
```

---

**문서 버전**: 1.0
**최종 수정**: 2025-01-22
