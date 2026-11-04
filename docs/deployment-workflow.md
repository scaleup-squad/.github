# 배포 워크플로우 가이드

GitHub Actions 로 무엇이 언제 검사·배포되는지 정리한다. 브랜치·PR 흐름은 [브랜치 전략 가이드](branching-strategy.md), 환경 구성은 [환경 구성 가이드](environment-setup-guide.md)를 본다.

> 워크플로의 실제 정의는 각 레포 `.github/workflows/` 가 정본이다. 이 문서는 구조만 요약한다.

---

## 언제 무엇이 도나

| 이벤트 | 무엇이 | 결과 |
|---|---|---|
| PR 생성·푸시 (`main` 대상) | CI — 타입 검사·린트·테스트 (+ gitleaks 비밀값 검사) | 실패하면 머지 불가 (main 보호 규칙) |
| `main` 푸시 (= PR 머지) | prod 배포 워크플로 | prod 자동 배포 |
| 수동 실행 `gh workflow run <파일> --ref <브랜치>` | 배포 워크플로 | GOS 앱은 staging 서버에 배포 (`main` 이면 prod 재배포) |

- **문서만 바뀐 푸시는 배포하지 않는다** — 배포 워크플로에 `paths-ignore`(`**.md`·`docs/**`·`tasks/**`·`.claude/**` 등).
- landing 은 PR 마다 미리보기가 자동으로 뜬다 (staging 서버 대신).

## 레포별 prod 배포

| 레포 | 워크플로 | 방식 |
|---|---|---|
| growthmaker-backend | `deploy.yml` | 검사 → 빌드 → **DB 마이그 적용** → EC2 무중단(블루/그린) 교체 → 스모크 테스트 |
| growthmaker-dashboard | `vercel-deploy.yml` | Vercel CLI 로 빌드·배포 → health 확인 |
| growthmaker-ai | `cd.yml` | Docker 이미지 빌드 → GHCR → 서버에서 pull·재기동 |
| growthmaker-automations | `deploy-prod.yml` | EC2 배포 → `/health` 실패 시 직전 커밋으로 자동 롤백 |
| growthmaker-landing | `deploy.yml` | 정적 export → S3 / CloudFront |
| growthmaker-ad-audit | `deploy.yml` | 검사 → EC2 배포 |
| growthmaker-ad-audit-web | `deploy.yml` | 정적 export → S3 / CloudFront |

**backend 마이그레이션 주의** — 배포 잡이 마이그 적용 → 코드 교체 순서로 돌기 때문에, 몇 분간 **새 스키마 + 옛 코드**가 함께 돈다. 새 제약을 바로 위반할 수 있는 마이그는 코드 배포와 PR 을 나눈다 (제약은 코드가 뜬 뒤 후속 PR).

## 배포 체크리스트

**머지 전**
- [ ] CI 통과
- [ ] (화면·동작 변경이면) staging 서버에 올려 확인 — 올리기 전 `gh run list --workflow <파일> --limit 3` 로 사용 중인지 확인
- [ ] 리드 승인

**머지 후**
- [ ] 배포 런 성공 확인 (Actions 탭 또는 `gh run list`)
- [ ] prod health·화면 확인
- [ ] 문제가 있으면 바로 롤백 (아래)

## 롤백

| 방법 | 언제 |
|---|---|
| 문제 PR 을 GitHub **Revert** → 생긴 PR 머지 | 기본. 모든 레포 공통 (머지 = 재배포) |
| `vercel promote <이전 배포 URL>` | dashboard 를 즉시 이전 배포로 되돌릴 때 (코드 Revert PR 은 따로) |
| landing `deploy.yml` 수동 실행 + `rollback_ref` | landing 을 특정 커밋으로 |
| 자동 | automations 는 `/health` 실패 시 스스로 직전 커밋으로 돌아간다 |

> DB 마이그레이션은 코드 Revert 로 되돌아가지 않는다. 되돌릴 수 없는 마이그(DROP·데이터 변경)는 머지 전에 리드 확인을 받는다.

## Secrets

배포용 비밀값은 각 레포의 GitHub Actions Secrets, 서비스 실행용 비밀값은 AWS Parameter Store 에 있다. 값·서버 주소는 공개 문서에 적지 않는다 — 필요하면 리드에게 요청.

---

**최종 수정**: 2026-11-04 (PR 단위 배포·staging 수동 배포·문서 푸시 배포 생략 반영)
