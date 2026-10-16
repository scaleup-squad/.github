# prod 배포 버전 태그 (composite actions)

prod(`main`) 배포·스모크가 성공하면 `vYYYY.MM.DD.N`(KST 날짜, N = 그 날 몇 번째, 레포별) 태그 + GitHub Release + Slack 알림을 남긴다(gos-harness #95).
앱의 공개 `/health` 가 `version`·`commit`·`deployedAt` 를 보여줄 수 있게 **이름은 배포 전에 정하고, 실물은 성공 후에 만든다.**

| 액션 | 언제 | 하는 일 | 권한 |
|---|---|---|---|
| `prod-version-plan` | 배포 **전** | 버전 이름 계산(읽기 전용) | `contents: read` |
| `prod-version-release` | 스모크 **성공 후** | 태그·Release 생성 또는 기존 Release 에 재배포 기록 + Slack | `contents: write` |

**reusable workflow 가 아니라 composite 인 이유** — prod 배포가 월 ~220회라 잡을 따로 띄우면 잡마다 1분 단위 과금이 붙는다. 호출 측 배포 잡 안의 스텝으로 돈다.

## 규칙

- **새 커밋 배포**(최신 태그보다 앞섬) → `mode=new`, `v<KST 오늘>.<오늘 최대 N + 1>`. 배포가 실패하면 이름은 버려지고 다음 배포가 같은 N 을 다시 쓴다(번호 구멍 없음).
- **같은 커밋 재배포 / 예전 커밋 롤백** → `mode=redeploy`, 새 태그 없음. 해당 태그의 Release "배포 기록" 에 한 줄 추가.
  - `version` = 그 커밋에 정확히 붙은 태그. 태그 없는 예전 커밋으로 롤백하면 **빈 값** — 앱은 `version` 이 비면 `commit` 으로 대신 표시할 것.
- 최신 태그가 배포 커밋과 갈라짐(강제 푸시 등) → 경고 후 `new`.
- 형식이 정확히 `v` + 날짜 + `.N`(0 으로 시작 X)인 태그만 센다. 다른 태그(`v1.2.3` 등)는 무시.

## 호출 측 배선

```yaml
jobs:
  deploy-prod:
    runs-on: ubuntu-latest
    # 같은 날 동시 prod 배포가 같은 N 을 계산하지 않게 — 아래 "태그 충돌" 참고
    concurrency: deploy-prod
    permissions:
      contents: write   # release 가 태그·Release 를 만든다 (plan 만 쓰면 read)
    steps:
      # ...checkout·build 등 기존 스텝...

      - id: pv
        if: github.ref == 'refs/heads/main'
        uses: scaleup-squad/.github/actions/prod-version-plan@<40자리 커밋 SHA>  # main @ YYYY-MM-DD — 아래 "버전 고정"
        with:
          token: ${{ github.token }}

      - name: Deploy
        env:
          # 빌드·런타임 env 로 넘긴다 (서버 .env, docker build-arg, vercel --build-env 등 레포 방식대로)
          APP_VERSION: ${{ steps.pv.outputs.version }}
          APP_COMMIT: ${{ steps.pv.outputs.commit }}
          APP_DEPLOYED_AT: ${{ steps.pv.outputs.deployed-at }}
        run: ./deploy.sh

      - name: Smoke
        run: ./smoke.sh

      - if: success() && github.ref == 'refs/heads/main'
        uses: scaleup-squad/.github/actions/prod-version-release@<40자리 커밋 SHA>  # main @ YYYY-MM-DD — 아래 "버전 고정"
        with:
          token: ${{ github.token }}
          version: ${{ steps.pv.outputs.version }}
          mode: ${{ steps.pv.outputs.mode }}
          previous-tag: ${{ steps.pv.outputs.previous-tag }}
          memo-tag: ${{ steps.pv.outputs.memo-tag }}
          service: backend
          note: ${{ inputs.note }}                          # 선택 — 예 "env 변경 재배포"
          slack-token: ${{ secrets.SLACK_BOT_TOKEN }}       # 비우면 Slack 건너뜀
          slack-channel: ${{ vars.SLACK_DEPLOY_CHANNEL }}
```

알아둘 것:
- **버전 고정** — `@main` 으로 부르지 말고 이 레포 커밋 SHA 로 고정한다. 이 액션은 `contents: write` 토큰을 받고 prod 배포 잡 안에서 도는데, `@main` 이면 이 레포 main 이 바뀌는 순간 모든 레포의 prod 배포가 바로 그 코드를 탄다. 올릴 땐 `gh api repos/scaleup-squad/.github/commits/main -q .sha` 로 SHA 를 받아 호출 레포마다 PR 로 바꾼다(변경 검토가 PR 에 남는다).
- **checkout 불필요** — 둘 다 GitHub API(`gh`·`jq`·`curl`)만 쓴다. GitHub 호스티드 러너엔 기본 설치. 셀프호스티드면 세 개가 있어야 한다.
- `sha` 기본값은 `github.sha`. 배포 커밋이 다르면(수동 재배포 워크플로 등) plan·release 에 **같은** 40자리 sha 를 넘길 것.
- plan 을 staging 에서도 돌리면 "다음 prod 이름" 이 나온다 — staging `/health` 엔 쓰지 말 것(위 예처럼 main 에서만).
- 태그 ruleset 이 있는 레포는 `GITHUB_TOKEN`(github-actions) 이 `v*` 태그를 만들 수 있게 해 둘 것.
- 실패 표시: 태그·Release 실패 = 스텝 실패(배포는 이미 됐다 — 기록이 빠졌다는 신호). Slack 실패 = 경고만.
- **plan 이 실패하면 배포 스텝도 돌지 않는다**(GitHub API 장애·rate limit·compare 404 등) — 의도된 동작이다. 버전 이름을 모른 채 배포하면 `/health` 와 태그가 어긋난다. 보통은 잠시 뒤 "Re-run jobs".
  - **비상 탈출구**(API 장애가 길고 prod 배포가 급할 때): 호출 측 `workflow_dispatch` 에 `skip-version` 같은 boolean 입력을 두고 plan 의 `if:` 에 `&& !inputs.skip-version` 을 더한다. plan 이 건너뛰어지면 `steps.pv.outputs.mode` 가 비므로 release 의 `if:` 에 `&& steps.pv.outputs.mode != ''` 를 넣어 같이 건너뛰게 한다. 이때 `APP_VERSION` 은 빈 값(앱은 `commit` 으로 표시), 태그·Release 는 남지 않는다 — 다음 정상 배포가 새 버전을 만든다.

## 설계 결정

- **Release 본문의 PR 목록** — GitHub 자동 노트(generate-notes)는 쓰지 않는다. 흐름이 feature PR →(squash) `staging` →(merge commit 반영 PR) `main` 이라 `main` 기준으론 "release: staging → main" 만 잡힌다.
  대신 compare API(`이전 태그...sha`) 커밋에서 꺼낸다(`notes.jq`): squash 커밋 제목 끝 `(#N)` + merge commit 으로 머지된 기능 PR(`Merge pull request #N from …` 의 본문 첫 줄). 반영 PR(`…/staging`)·역반영(`…/main`) merge 와 번호 없는 커밋은 뺀다. PR 번호로 중복 제거.
  compare 는 100개씩 끝까지 넘겨 받지만 GitHub 쪽 상한이 있어, 받은 커밋 수 < `total_commits` 면 본문에 "잘렸다" 고 쓰고 비교 링크를 남긴다.
- **태그 충돌(422)** — 이미 있는 태그가 **같은 커밋**이면 같은 배포의 재실행으로 보고 통과(Release 가 이미 있으면 덮어쓰지 않음). **다른 커밋**이면 실패 — 이 배포의 `/health` 는 이미 그 이름으로 떴으니 N 을 몰래 올리면 `/health` 와 태그가 어긋난다. 사람이 정리한다. 배포 잡에 `concurrency` 를 걸면 생기지 않는다.
- **태그는 있는데 Release 가 없는 경우** — 두 가지라 "그 태그 앞에 형식 맞는 태그가 있는가" 로 가른다.
  - **재실행 보완**(앞 태그 있음): 1차 런이 태그까지 만들고 Release·compare 에서 실패한 뒤 "Re-run jobs" 하면, plan 은 그 태그를 보고 `redeploy` 로 판단한다. release 는 이를 알아보고 원래 했어야 할 일 — 앞 태그 기준 PR 목록 Release + `:rocket:` 배포 완료 알림 — 을 마저 한다. (예전 태그로 롤백했는데 그 Release 가 빠져 있던 경우도 목록은 채우고, 기록·알림은 롤백으로)
  - **사람이 단 기준 태그**(앞 태그 없음): 목록을 만들 수 없으니 최소 Release 를 만들어 배포 기록만 남긴다.
  - 둘 다 그 태그가 최신일 때만 Latest 로 표시.
- **입력 형식 검증** — release 는 `version`·`previous-tag`·`memo-tag` 가 비어 있지 않으면 plan 과 같은 형식 정규식으로 검사하고, 어긋나면 아무것도 만들지 않고 실패한다(스텝 id 오타 등 배선 실수 방지).
- **@멘션** — PR 제목의 `@user`·`@org/team` 은 Release 본문에서 백틱으로 감싼다. Release 발행 때 멘션 알림이 가지 않게.

## 첫 도입 — 기준 태그

각 레포 현재 prod 커밋에 사람이 한 번 같은 형식으로 태그를 단다(Release 는 없어도 된다 — 첫 재배포 때 최소 Release 가 생긴다).

```bash
git tag v2026.10.15.1 <현재 prod 커밋> && git push origin v2026.10.15.1
```

기준 태그가 없으면 첫 Release 본문엔 "이전 버전 태그가 없어 목록을 만들 수 없다" 고 쓴다.

## 로컬 확인

```bash
bash actions/tests/run.sh   # 가짜 gh 로 계산·분기·본문·422 처리 (네트워크 없음)

# 실제 레포 대상 — plan 은 읽기 전용, release 는 DRY_RUN=1 이면 쓰기 대신 내용만 출력
REPO=scaleup-squad/growthmaker-landing SHA=<40자리> bash actions/prod-version-plan/plan.sh
DRY_RUN=1 REPO=… SHA=… MODE=new VERSION=… PREVIOUS_TAG=… SERVICE=landing RUN_URL=https://example \
  bash actions/prod-version-release/release.sh
```
