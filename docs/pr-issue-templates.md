# PR/Issue 템플릿 가이드

GitHub PR 및 Issue 작성 가이드입니다.

## 목차

- [PR 템플릿](#pr-템플릿)
- [Issue 템플릿](#issue-템플릿)
- [템플릿 파일 위치](#템플릿-파일-위치)

---

## PR 템플릿

PR 생성 시 자동으로 템플릿이 적용됩니다.

### 필수 항목

| 항목 | 설명 |
|------|------|
| **변경 사항** | 이 PR에서 변경된 내용 요약 |
| **변경 유형** | 버그 수정, 새 기능, Breaking Change 등 |
| **테스트 방법** | 변경 사항을 테스트하는 방법 |
| **체크리스트** | 머지 전 확인사항 |

### PR 제목 규칙

```
<type>: <description>

예시:
feat: 사용자 인증 기능 추가
fix: 로그인 오류 수정
refactor: 테이블 컴포넌트 리팩토링
docs: README 업데이트
chore: 의존성 업데이트
```

### 체크리스트

- [ ] 로컬에서 빌드/테스트 통과 확인
- [ ] 불필요한 console.log 제거
- [ ] 코드 리뷰 요청
- [ ] 관련 문서 업데이트 (필요시)

---

## Issue 템플릿

### 버그 리포트

버그 발견 시 사용합니다.

**필수 항목:**
- 버그 설명
- 재현 방법
- 예상 동작 vs 실제 동작
- 환경 정보

### 기능 요청

새로운 기능 제안 시 사용합니다.

**필수 항목:**
- 기능 설명
- 배경 / 필요성
- 제안하는 해결 방법

---

## 템플릿 파일 위치

```
.github/
├── CODEOWNERS
├── PULL_REQUEST_TEMPLATE.md
└── ISSUE_TEMPLATE/
    ├── bug_report.md
    ├── feature_request.md
    └── config.yml
```

### 각 파일 설명

| 파일 | 설명 |
|------|------|
| `CODEOWNERS` | PR 리뷰어 자동 지정 |
| `PULL_REQUEST_TEMPLATE.md` | PR 생성 시 기본 템플릿 |
| `ISSUE_TEMPLATE/bug_report.md` | 버그 리포트 템플릿 |
| `ISSUE_TEMPLATE/feature_request.md` | 기능 요청 템플릿 |
| `ISSUE_TEMPLATE/config.yml` | Issue 템플릿 설정 |

---

## 적용 현황

| 레포지토리 | CODEOWNERS | PR 템플릿 | Issue 템플릿 |
|------------|------------|-----------|--------------|
| growthmaker-dashboard | ✅ | ✅ | ✅ |
| growthmaker-backend | ✅ | ✅ | ✅ |

---

**문서 버전**: 1.0
**최종 수정**: 2026-01-22
