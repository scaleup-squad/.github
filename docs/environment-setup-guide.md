# 환경 구성 가이드 (local / staging / prod)

GOS 앱(backend·dashboard·ai·automations)이 어느 환경에서 어떻게 돌고, 무엇이 무엇을 바라보는지 정리한다.
배포 흐름은 [브랜치 전략 가이드](branching-strategy.md)가 정본이다.

> 서버 주소·키·접속 방법 같은 운영 세부는 공개 문서에 두지 않는다 — 조직 내부 문서(`.github-private`·`gos-harness` runbook)를 본다.

---

## 환경 3개

| | local | staging | prod |
|---|---|---|---|
| 목적 | 각자 개발 | 머지 전 공용 미리보기 (서버 1대 공유) | 실 서비스 |
| 어떻게 올라가나 | 각자 PC 에서 실행 | 확인할 브랜치를 수동 실행(`gh workflow run … --ref <브랜치>`) | `main` 머지 = 자동 배포 |
| backend | `localhost:8787` | `staging-api.growthmaker.kr` | `api.growthmaker.kr` |
| dashboard | `localhost:3000` | `gos-dev.vercel.app` (Vercel Preview) | `app.growthmaker.kr` (Vercel Production) |
| ai | `localhost:8000` | staging 서버 (backend 를 통해서만 호출) | prod 서버 (backend 를 통해서만 호출) |
| automations | 필요 시 로컬 | staging 서버 | prod 서버 |
| DB (Supabase) | 로컬 Supabase (`npx supabase start`) | **staging 프로젝트** (익명 시드 데이터) | **prod 프로젝트** |

- **prod 와 staging 은 Supabase 프로젝트가 따로다.** staging 데이터는 익명화된 시드라 마음껏 써도 된다.
- dashboard 의 **모든 PR 미리보기(Vercel Preview)도 staging backend·DB 를 바라본다** — 의도된 설정.
- dashboard 는 ai 를 직접 부르지 않는다. 항상 backend 의 `/api/ai/*` 프록시를 거친다.
- agent 는 prod 서버에서만 돈다. landing 은 staging 대신 PR 미리보기로 확인한다.

## 비밀값·환경 변수

| 대상 | 정본 | 바꾸는 법 |
|---|---|---|
| 서버에서 도는 서비스 (backend·ai·automations·agent) | AWS Parameter Store `/gos/{stage}/{service}/` — 기동 시 주입 | 값 수정 후 재배포 |
| dashboard | Vercel 프로젝트 환경 변수 (Production / Preview) | `vercel env add/rm` → 배포 워크플로 수동 실행 |
| 로컬 개발 | 각 레포 `.env.example` 복사 (기본값은 로컬 안전값). 외부 연동이 필요할 때만 조직 금고(Bitwarden) staging 컬렉션 | — |

- prod 비밀값은 리드만 다룬다. 로컬·staging 은 staging 값만 쓴다.
- 비밀값을 Slack·이슈·PR·채팅에 평문으로 붙이지 않는다.

## DB 스키마 (Supabase)

- 모든 레포의 스키마 변경은 **growthmaker-backend `supabase/migrations/`** 가 정본이다 (다른 레포는 마이그 파일을 두지 않는다).
- 적용은 backend 배포 잡이 한다 — staging 서버에 올리면 staging DB, `main` 에 머지하면 prod DB.
- 타입은 `@scaleup-squad/platform-kit` 이 prod 스키마에서 자동 생성한다. 스키마가 바뀌면 각 레포에 `auto/platform-kit-*` PR 이 열린다 → 하나씩 머지.

## 상태 확인 (health)

| 서비스 | staging | prod |
|---|---|---|
| backend | `https://staging-api.growthmaker.kr/health` | `https://api.growthmaker.kr/health` |
| ai | 배포 워크플로의 `Deploy to Staging` 단계가 확인 | `https://api.growthmaker.kr/ai/health` |
| dashboard | `https://gos-dev.vercel.app` | `https://app.growthmaker.kr` |

> 예전 경로 `api.growthmaker.kr/stage`·`/dev`·`/ai-stage` 는 폐지됐다 (410 응답). Development 환경과 `develop` 브랜치도 운영하지 않는다.

## 함께 볼 문서

- [브랜치 전략](branching-strategy.md) — 브랜치·PR·staging 올리기·머지
- [배포 워크플로우](deployment-workflow.md) — CI/CD 파이프라인 구조

---

**최종 수정**: 2026-11-04 (staging 전용 서버·DB 분리, staging 브랜치 폐지 반영)
