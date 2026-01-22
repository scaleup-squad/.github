# 브랜치 전략 가이드

ScaleUp Squad의 Git 브랜치 관리 전략을 설명합니다.

## 목차

- [브랜치 구조](#브랜치-구조)
- [브랜치 네이밍 규칙](#브랜치-네이밍-규칙)
- [작업 흐름](#작업-흐름)
- [Pull Request 규칙](#pull-request-규칙)
- [긴급 배포 (Hotfix)](#긴급-배포-hotfix)

---

## 브랜치 구조

### 메인 브랜치

```
main (production)
  │
  └── staging
        │
        └── develop
              │
              ├── feature/xxx
              ├── bugfix/xxx
              └── hotfix/xxx
```

| 브랜치 | 목적 | 보호 규칙 |
|--------|------|-----------|
| `main` | Production 배포 | Protected, PR 필수 |
| `staging` | QA/Staging 배포 | Protected, PR 필수 |
| `develop` | 개발 통합 | Protected, PR 필수 |

### 작업 브랜치

| 브랜치 타입 | 네이밍 | 용도 | 시작점 | 머지 대상 |
|-------------|--------|------|--------|-----------|
| `feature/*` | `feature/기능명` | 새 기능 개발 | `develop` | `develop` |
| `bugfix/*` | `bugfix/버그명` | 버그 수정 | `develop` | `develop` |
| `hotfix/*` | `hotfix/이슈명` | 긴급 수정 | `main` | `main` → `develop` |
| `release/*` | `release/v1.0.0` | 릴리즈 준비 | `staging` | `main` |

---

## 브랜치 네이밍 규칙

### 형식

```
<type>/<description>
```

### 예시

```bash
# 기능 개발
feature/user-authentication
feature/export-csv
feature/dark-mode

# 버그 수정
bugfix/login-error
bugfix/table-sorting

# 긴급 수정
hotfix/security-patch
hotfix/critical-api-fix

# 릴리즈
release/v1.2.0
```

### 규칙

- 영문 소문자와 하이픈(`-`) 사용
- 간결하고 명확한 설명
- 이슈 번호가 있으면 포함 가능: `feature/123-user-auth`

---

## 작업 흐름

### 1. 일반 기능 개발

```bash
# 1. develop에서 feature 브랜치 생성
git checkout develop
git pull origin develop
git checkout -b feature/new-feature

# 2. 작업 후 커밋
git add .
git commit -m "feat: 새로운 기능 추가"

# 3. develop에 PR 생성
git push -u origin feature/new-feature
# GitHub에서 PR 생성: feature/new-feature → develop

# 4. 코드 리뷰 후 머지
# PR 승인 후 Squash and merge
```

### 2. Staging 배포

```bash
# develop → staging PR 생성
# 테스트 완료 후 머지
```

### 3. Production 배포

```bash
# staging → main PR 생성
# 최종 검증 후 머지
```

### 전체 흐름 다이어그램

```
[개발자] feature/xxx 브랜치에서 작업
           │
           ▼ PR & Code Review
           │
        develop ──────────────────► Dev 환경 자동 배포
           │
           ▼ QA 테스트 요청
           │
        staging ──────────────────► Staging 환경 자동 배포
           │
           ▼ QA 승인 & 최종 검증
           │
         main ────────────────────► Production 환경 배포
```

---

## Pull Request 규칙

### PR 생성 시 체크리스트

- [ ] 코드가 정상적으로 빌드되는가?
- [ ] 테스트가 통과하는가?
- [ ] 불필요한 console.log나 주석이 제거되었는가?
- [ ] 환경 변수가 올바르게 설정되었는가?

### PR 제목 형식

```
<type>: <description>

예시:
feat: 사용자 인증 기능 추가
fix: 로그인 오류 수정
refactor: 테이블 컴포넌트 리팩토링
docs: README 업데이트
```

### PR 본문 템플릿

```markdown
## 변경 사항
- 변경 내용 1
- 변경 내용 2

## 테스트 방법
1. 테스트 단계 1
2. 테스트 단계 2

## 스크린샷 (해당되는 경우)

## 관련 이슈
- Closes #123
```

### 머지 전략

| 대상 브랜치 | 머지 방식 | 이유 |
|-------------|-----------|------|
| `develop` | Squash and merge | 깔끔한 히스토리 유지 |
| `staging` | Create a merge commit | 변경 이력 보존 |
| `main` | Create a merge commit | 변경 이력 보존 |

---

## 긴급 배포 (Hotfix)

Production에서 긴급한 버그가 발견된 경우:

```bash
# 1. main에서 hotfix 브랜치 생성
git checkout main
git pull origin main
git checkout -b hotfix/critical-bug

# 2. 수정 후 커밋
git add .
git commit -m "fix: 긴급 버그 수정"

# 3. main에 직접 PR 생성
git push -u origin hotfix/critical-bug
# PR: hotfix/critical-bug → main

# 4. main 머지 후 develop에도 반영
git checkout develop
git pull origin main
git push origin develop
```

### Hotfix 흐름

```
         main
           │
           ├── hotfix/xxx 생성
           │         │
           │         ▼ 수정 작업
           │         │
           ◄─────────┘ main에 머지
           │
           ▼
       develop에도 머지 (충돌 해결)
```

---

## 브랜치 정리

### 정기 정리

```bash
# 머지된 로컬 브랜치 삭제
git branch --merged | grep -v "\*\|main\|develop\|staging" | xargs -n 1 git branch -d

# 원격에서 삭제된 브랜치 정리
git fetch --prune
```

### GitHub 설정

- **Automatically delete head branches**: PR 머지 후 자동 삭제 활성화
- Settings > General > Pull Requests > Automatically delete head branches ✅

---

## 다음 단계

- [배포 워크플로우](./deployment-workflow.md) - CI/CD 파이프라인 설정

---

**문서 버전**: 1.0
**최종 수정**: 2025-01-22
