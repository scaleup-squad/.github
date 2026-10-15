#!/usr/bin/env bash
# prod-version-plan / prod-version-release 로컬 테스트 — 네트워크 없이 가짜 gh 로 돈다.
#   bash actions/tests/run.sh
# 실제 레포 대상 확인은 README 의 "로컬 확인" 참고(읽기 전용 / DRY_RUN).
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export RUNNER_TEMP=$WORK
unset GITHUB_OUTPUT

# ── 가짜 gh: 호출을 기록하고, 경로별로 FX_* env 의 응답을 돌려준다 ──────────────────────────
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$WORK/calls.log"
[ "$1" = api ] || exit 2
shift
method=GET jq_expr="" path="" input=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X) method=$2; shift 2 ;;
    --jq) jq_expr=$2; shift 2 ;;
    --input) input=$(cat); shift 2 ;;
    -f|-F) shift 2 ;;
    --paginate) shift ;;
    *) path=$1; shift ;;
  esac
done
[ -n "$input" ] && printf '%s\n' "$input" >> "$WORK/inputs.log"
out() { if [ -n "$jq_expr" ]; then jq -r "$jq_expr"; else cat; fi; }
nf() { echo '{"message":"Not Found"}'; echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
case "$method $path" in
  "GET "*/git/matching-refs/tags/v) printf '%s' "${FX_REFS:-[]}" | out ;;
  "GET "*/compare/*"?per_page=100") printf '%s' "$FX_COMPARE_PAGES" ;;
  "GET "*/compare/*) printf '{"status":"%s"}' "$FX_STATUS" | out ;;
  "GET "*/git/tags/*) printf '{"object":{"sha":"%s"}}' "$FX_ANNOTATED_TARGET" | out ;;
  "GET "*/git/ref/tags/*) [ -n "${FX_EXISTING_TAG_SHA:-}" ] || nf
                          printf '{"object":{"type":"commit","sha":"%s"}}' "$FX_EXISTING_TAG_SHA" | out ;;
  "GET "*/releases/tags/*) [ -n "${FX_RELEASE:-}" ] || nf; printf '%s' "$FX_RELEASE" | out ;;
  "POST "*/git/refs) [ -z "${FX_TAG_422:-}" ] || { echo "gh: Reference already exists (HTTP 422)" >&2; exit 1; }
                     echo '{}' ;;
  "POST "*/releases) echo '{"html_url":"https://example/rel/new"}' | out ;;
  "PATCH "*/releases/*) echo '{"html_url":"https://example/rel/1"}' | out ;;
  *) echo "stub: 모르는 호출 $method $path" >&2; exit 3 ;;
esac
STUB
# 가짜 curl(Slack): 보낸 페이로드만 기록
cat > "$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do [ "$1" = --data ] && printf '%s\n' "$2" >> "$WORK/slack.log"; shift; done
echo '{"ok":true}'
STUB
chmod +x "$WORK/bin/gh" "$WORK/bin/curl"
export PATH="$WORK/bin:$PATH" WORK

PASS=0 FAIL=0
eq() { # $1=이름 $2=기대 $3=실제
  if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"
  else FAIL=$((FAIL + 1)); echo "FAIL $1"; echo "     기대: $2"; echo "     실제: $3"; fi
}
has() { # $1=이름 $2=찾을 문자열 $3=본문
  if grep -qF -- "$2" <<< "$3"; then PASS=$((PASS + 1)); echo "ok   $1"
  else FAIL=$((FAIL + 1)); echo "FAIL $1 — '$2' 없음"; printf '%s\n' "$3" | sed 's/^/     /'; fi
}

SHA=1111111111111111111111111111111111111111
OLD=2222222222222222222222222222222222222222
OTHER=3333333333333333333333333333333333333333

# ── 1. 순수 함수: 정렬·다음 버전·mode 판단 ─────────────────────────────────────────────────
(
  # shellcheck source=/dev/null
  source "$ROOT/prod-version-plan/plan.sh"
  TAGS='v2026.10.15.9
v2026.10.15.10
v2026.10.14.30
v2026.10.15
v2026.10.15.03
v2026.10.15.0
v1.2.3
v2026.10.15.2-rc
release-1
v2026.10.15.2'
  eq "정렬: .10 이 .9 보다 최신" "v2026.10.15.10" "$(sort_tags <<< "$TAGS" | tail -n 1)"
  eq "형식 밖 태그 제외(날짜만·0 시작·rc·semver)" "v2026.10.14.30 v2026.10.15.2 v2026.10.15.9 v2026.10.15.10" "$(sort_tags <<< "$TAGS" | xargs)"
  eq "오늘 N = 오늘 최대+1 (두 자리)" "v2026.10.15.11" "$(next_version 2026.10.15 <<< "$TAGS")"
  eq "다른 날짜 태그는 N 에 무관 — 새 날은 1" "v2026.10.16.1" "$(next_version 2026.10.16 <<< "$TAGS")"
  eq "어제 N=30 이어도 오늘은 무관" "v2026.10.14.31" "$(next_version 2026.10.14 <<< "$TAGS")"
  eq "태그 없음 → .1" "v2026.10.15.1" "$(next_version 2026.10.15 <<< "")"
  eq "해 넘김 정렬" "v2027.01.01.1" "$(printf 'v2026.12.31.9\nv2027.01.01.1\nv2026.12.31.10\n' | sort_tags | tail -n 1)"
  eq "월 두 자리 정렬(09 < 10)" "v2026.10.01.1" "$(printf 'v2026.10.01.1\nv2026.09.30.5\n' | sort_tags | tail -n 1)"
  eq "mode: 태그 없음" new "$(decide_mode "")"
  eq "mode: ahead" new "$(decide_mode ahead)"
  eq "mode: identical" redeploy "$(decide_mode identical)"
  eq "mode: behind" redeploy "$(decide_mode behind)"
  eq "mode: diverged → new" new "$(decide_mode diverged 2>/dev/null)"
  has "mode: diverged 경고" "::warning::" "$(decide_mode diverged 2>&1 >/dev/null)"
  if decide_mode weird >/dev/null 2>&1; then eq "mode: 모르는 status 는 실패" 1 0; else eq "mode: 모르는 status 는 실패" 1 1; fi
  echo "PASS=$PASS FAIL=$FAIL" > "$WORK/sub1"
)
# shellcheck disable=SC1091
source "$WORK/sub1"

# ── 2. plan.sh 전체(가짜 gh) ────────────────────────────────────────────────────────────────
ref() { printf '{"ref":"refs/tags/%s","object":{"type":"%s","sha":"%s"}}' "$1" "$2" "$3"; }
plan() { REPO=o/r SHA=$SHA PV_TODAY=2026.10.15 bash "$ROOT/prod-version-plan/plan.sh" 2>"$WORK/err"; }
field() { grep "^$1=" <<< "$2" | cut -d= -f2-; }

FX_REFS="[$(ref v2026.10.15.9 commit $OLD),$(ref v2026.10.15.10 commit $OTHER),$(ref v2026.10.14.1 tag aaaa),$(ref vfoo commit $SHA)]"
export FX_REFS
export FX_ANNOTATED_TARGET=$SHA

out=$(FX_STATUS=ahead plan)
eq "plan ahead: mode" new "$(field mode "$out")"
eq "plan ahead: version" v2026.10.15.11 "$(field version "$out")"
eq "plan ahead: previous-tag" v2026.10.15.10 "$(field previous-tag "$out")"
eq "plan ahead: memo-tag 빈 값" "" "$(field memo-tag "$out")"
eq "plan: commit 7자리" 1111111 "$(field commit "$out")"
has "plan: deployed-at ISO UTC" "Z" "$(field deployed-at "$out")"
has "plan: compare 기준 = 최신 태그" "compare/refs/tags/v2026.10.15.10...$SHA" "$(cat "$WORK/calls.log")"

# 롤백: sha 에 정확히 붙은 건 annotated 기준 태그 v2026.10.14.1(→ $SHA)
out=$(FX_STATUS=behind plan)
eq "plan behind(태그 있음): mode" redeploy "$(field mode "$out")"
eq "plan behind: version = sha 에 붙은 태그(annotated 따라감)" v2026.10.14.1 "$(field version "$out")"
eq "plan behind: memo-tag = 그 태그" v2026.10.14.1 "$(field memo-tag "$out")"

out=$(FX_STATUS=behind FX_ANNOTATED_TARGET=$OLD plan)
eq "plan behind(미태그 커밋): version 빈 값" "" "$(field version "$out")"
eq "plan behind(미태그 커밋): memo-tag = 최신" v2026.10.15.10 "$(field memo-tag "$out")"

ONE="[$(ref v2026.10.15.1 commit $SHA)]"
out=$(FX_REFS=$ONE FX_STATUS=identical plan)
eq "plan identical: redeploy" redeploy "$(field mode "$out")"
eq "plan identical: version = 최신 태그" v2026.10.15.1 "$(field version "$out")"

out=$(FX_REFS=$ONE FX_STATUS=diverged plan)
eq "plan diverged: new" new "$(field mode "$out")"
has "plan diverged: 경고" "::warning::" "$(cat "$WORK/err")"

: > "$WORK/calls.log"
out=$(FX_REFS='[]' plan)
eq "plan 태그 없음: new .1" "new v2026.10.15.1" "$(field mode "$out") $(field version "$out")"
eq "plan 태그 없음: compare 호출 안 함" 0 "$(grep -c compare "$WORK/calls.log" || true)"

GITHUB_OUTPUT=$WORK/gho FX_REFS='[]' plan > /dev/null
eq "plan: GITHUB_OUTPUT 기록" 6 "$(wc -l < "$WORK/gho" | tr -d ' ')"

# ── 3. notes.jq — 실제 backend main 이력 모양 ───────────────────────────────────────────────
c() { jq -n --arg m "$1" --argjson p "$2" '{commit: {message: $m}, parents: [range($p)]}'; }
PAGE1=$(jq -n --argjson a "$(c 'fix(ci): release-pr 목록 정리' 1)" \
  --argjson b "$(c $'Merge pull request #1338 from scaleup-squad/fix/release-pr-list-by-pr\n\nfix(ci): 반영 PR 목록을 PR 단위로' 2)" \
  --argjson c "$(c 'feat(gdash): v3 P5 ① data prep (#1325)' 1)" \
  --argjson d "$(c $'Merge pull request #1340 from scaleup-squad/staging\n\nrelease: staging → main (3건)' 2)" \
  '{total_commits: 7, commits: [$a, $b, $c, $d]}')
PAGE2=$(jq -n --argjson a "$(c 'chore(deps): platform-kit 0.1.30 (#1343)' 1)" \
  --argjson b "$(c $'Merge pull request #1346 from scaleup-squad/main\n\nsync: main → staging' 2)" \
  --argjson c "$(c 'feat(gdash): v3 P5 ① data prep (#1325)' 1)" \
  '{total_commits: 7, commits: [$a, $b, $c]}')
NOTES=$(printf '%s\n%s\n' "$PAGE1" "$PAGE2" | jq -rs -f "$ROOT/prod-version-release/notes.jq")
eq "notes: squash·merge PR 만, staging/main 통로 제외, 중복 제거, 시간순" \
"- fix(ci): 반영 PR 목록을 PR 단위로 (#1338)
- feat(gdash): v3 P5 ① data prep (#1325)
- chore(deps): platform-kit 0.1.30 (#1343)" "$NOTES"

# ── 4. release.sh ──────────────────────────────────────────────────────────────────────────
rel() { REPO=o/r SHA=$SHA SERVICE=backend RUN_URL=https://run/1 bash "$ROOT/prod-version-release/release.sh" 2>&1; }
unset FX_REFS FX_STATUS FX_ANNOTATED_TARGET
export FX_COMPARE_PAGES
FX_COMPARE_PAGES=$(printf '%s\n%s\n' "$PAGE1" "$PAGE2")

: > "$WORK/inputs.log"
out=$(MODE=new VERSION=v2026.10.15.11 PREVIOUS_TAG=v2026.10.15.10 rel)
has "release new: 태그 생성" "태그 생성: v2026.10.15.11" "$out"
body=$(jq -r .body "$WORK/inputs.log")
has "release new: 본문에 PR 목록" "- chore(deps): platform-kit 0.1.30 (#1343)" "$body"
has "release new: 비교 링크" "compare/v2026.10.15.10...v2026.10.15.11" "$body"
has "release new: 배포 기록 + run" "[run](https://run/1)" "$body"
eq "release new: Latest" true "$(jq -r .make_latest "$WORK/inputs.log")"
has "release new: Slack 없으면 notice" "Slack 알림은 건너뛴다" "$out"

: > "$WORK/inputs.log"
out=$(MODE=new VERSION=v2026.10.15.1 PREVIOUS_TAG='' rel)
has "release new(이전 태그 없음): 안내" "이전 버전 태그가 없어" "$(jq -r .body "$WORK/inputs.log")"

# 같은 커밋 재실행: 422 + 기존 태그가 같은 sha → 통과
out=$(MODE=new VERSION=v2026.10.15.11 PREVIOUS_TAG=v2026.10.15.10 FX_TAG_422=1 FX_EXISTING_TAG_SHA=$SHA rel); rc=$?
eq "release 422(같은 커밋): 성공" 0 $rc
has "release 422(같은 커밋): notice" "이미 같은 커밋에" "$out"
# 동시 배포: 422 + 다른 sha → 실패
set +e
out=$(MODE=new VERSION=v2026.10.15.11 PREVIOUS_TAG=v2026.10.15.10 FX_TAG_422=1 FX_EXISTING_TAG_SHA=$OTHER rel); rc=$?
set -e
eq "release 422(다른 커밋): 실패" 1 $rc
has "release 422(다른 커밋): 이유" "동시 배포 의심" "$out"

# 재실행인데 Release 도 이미 있음 → 덮어쓰지 않음
: > "$WORK/inputs.log"
out=$(MODE=new VERSION=v2026.10.15.11 FX_TAG_422=1 FX_EXISTING_TAG_SHA=$SHA FX_RELEASE='{"id":1,"html_url":"https://example/rel/1","body":"x"}' rel)
eq "release new 재실행: Release 안 건드림" "" "$(cat "$WORK/inputs.log")"

# 재배포: 기존 Release 본문 끝에 한 줄
: > "$WORK/inputs.log"; : > "$WORK/calls.log"
out=$(MODE=redeploy VERSION=v2026.10.15.10 PREVIOUS_TAG=v2026.10.15.10 MEMO_TAG=v2026.10.15.10 NOTE='env 변경 재배포' \
  FX_RELEASE=$'{"id":1,"html_url":"https://example/rel/1","body":"요약\\n\\n## 배포 기록\\n- 첫 배포"}' rel)
body=$(jq -r .body "$WORK/inputs.log")
has "redeploy: 기존 본문 보존" "- 첫 배포" "$body"
has "redeploy: 재배포 줄" "재배포: \`1111111\` (env 변경 재배포) [run](https://run/1)" "$body"
eq "redeploy: 기록 구역 1개" 1 "$(grep -c '^## 배포 기록' <<< "$body")"
eq "redeploy: 태그 생성 안 함" 0 "$(grep -c 'git/refs' "$WORK/calls.log" || true)"

# 롤백 + 기준 태그(Release 없음) → 최소 Release 생성, 최신 아니면 Latest 아님
: > "$WORK/inputs.log"
out=$(MODE=redeploy VERSION='' PREVIOUS_TAG=v2026.10.15.10 MEMO_TAG=v2026.10.01.1 rel)
has "rollback: 최소 Release 생성" "최소 Release 생성" "$out"
has "rollback: 롤백 줄" "롤백: \`1111111\`" "$(jq -r .body "$WORK/inputs.log")"
eq "rollback: 예전 태그는 Latest 아님" false "$(jq -r .make_latest "$WORK/inputs.log")"

# Slack: 토큰 있으면 DRY_RUN 에서 페이로드 확인
out=$(DRY_RUN=1 MODE=new VERSION=v2026.10.15.11 PREVIOUS_TAG=v2026.10.15.10 SLACK_TOKEN=x SLACK_CHANNEL=C1 rel)
has "slack: 메시지" "prod 배포 완료 — *v2026.10.15.11*" "$out"
has "dry-run: 쓰기 안 함" "[dry-run] gh api -X POST repos/o/r/git/refs" "$out"

# 입력 형식 검증 — plan 출력 배선 오류로 엉뚱한 태그가 생기지 않게
set +e
out=$(MODE=new VERSION=v2026.10.15 rel); rc=$?
eq "검증: version 형식 밖 → 실패" 1 $rc
has "검증: 이유" "버전 형식" "$out"
out=$(MODE=redeploy MEMO_TAG=steps.x.outputs.memo-tag rel); rc=$?
eq "검증: memo-tag 형식 밖 → 실패" 1 $rc
out=$(MODE=new VERSION='' rel); rc=$?
eq "검증: new 인데 version 빈 값 → 실패" 1 $rc
set -e

# notes.jq: @멘션 무력화
eq "notes: @멘션은 백틱, 이메일은 그대로" "- thanks \`@kim-1\` \`@o/devs\` a@b.com (#5)" \
  "$(jq -n '{commits: [{commit: {message: "thanks @kim-1 @o/devs a@b.com (#5)"}, parents: [1]}]}' | jq -rs -f "$ROOT/prod-version-release/notes.jq")"

# ── 5. plan → release 연결(end-to-end) ─────────────────────────────────────────────────────
# 1차 런이 태그까지 만들고 Release 에서 실패 → "Re-run jobs". plan 은 태그를 보고 redeploy 로 판단하지만
# release 는 원래 했어야 할 일(PR 목록 Release + :rocket:)을 마저 해야 한다.
chain() { # plan 출력을 그대로 release 입력으로
  local p
  p=$(REPO=o/r SHA=$SHA PV_TODAY=2026.10.15 bash "$ROOT/prod-version-plan/plan.sh" 2>/dev/null)
  REPO=o/r SHA=$SHA SERVICE=backend RUN_URL=https://run/2 SLACK_TOKEN=x SLACK_CHANNEL=C1 \
    MODE=$(field mode "$p") VERSION=$(field version "$p") PREVIOUS_TAG=$(field previous-tag "$p") \
    MEMO_TAG=$(field memo-tag "$p") bash "$ROOT/prod-version-release/release.sh" 2>&1
}
: > "$WORK/inputs.log"; : > "$WORK/slack.log"
out=$(FX_REFS="[$(ref v2026.10.14.3 commit $OLD),$(ref v2026.10.15.1 commit $SHA)]" FX_STATUS=identical chain)
has "e2e 재실행: 보완 경로" "재실행 보완으로 전체 Release 생성" "$out"
body=$(jq -r .body "$WORK/inputs.log")
has "e2e 재실행: 앞 태그 기준 PR 목록" "## 포함된 변경 (v2026.10.14.3 이후)" "$body"
has "e2e 재실행: PR 줄" "- chore(deps): platform-kit 0.1.30 (#1343)" "$body"
has "e2e 재실행: compare 범위" "compare/refs/tags/v2026.10.14.3...$SHA?per_page=100" "$(cat "$WORK/calls.log")"
eq "e2e 재실행: Release 태그" v2026.10.15.1 "$(jq -r .tag_name "$WORK/inputs.log")"
eq "e2e 재실행: Latest" true "$(jq -r .make_latest "$WORK/inputs.log")"
has "e2e 재실행: Slack :rocket:" ":rocket: *backend* prod 배포 완료 — *v2026.10.15.1*" "$(jq -r .text "$WORK/slack.log")"
eq "e2e 재실행: 태그 새로 안 만듦" 0 "$(grep -c 'POST repos/o/r/git/refs' "$WORK/calls.log" || true)"

# 진짜 기준 태그(앞 태그 없음, annotated) — 최소 Release + :repeat: 재배포
: > "$WORK/inputs.log"; : > "$WORK/slack.log"
out=$(FX_REFS="[$(ref v2026.10.01.1 tag bbbb)]" FX_ANNOTATED_TARGET=$SHA FX_STATUS=identical chain)
has "e2e 기준 태그: 최소 Release" "최소 Release 생성" "$out"
has "e2e 기준 태그: 본문" "기준 태그 — 자동 Release 이전" "$(jq -r .body "$WORK/inputs.log")"
eq "e2e 기준 태그: Latest(최신이라)" true "$(jq -r .make_latest "$WORK/inputs.log")"
has "e2e 기준 태그: Slack 재배포" ":repeat: *backend* prod 재배포" "$(jq -r .text "$WORK/slack.log")"

# 정상 첫 배포(새 커밋) — 태그 생성 + 전체 Release
: > "$WORK/inputs.log"; : > "$WORK/calls.log"
out=$(FX_REFS="[$(ref v2026.10.15.1 commit $OLD)]" FX_STATUS=ahead chain)
has "e2e 새 배포: 태그" "태그 생성: v2026.10.15.2" "$out"
has "e2e 새 배포: 목록 기준" "## 포함된 변경 (v2026.10.15.1 이후)" "$(jq -r .body "$WORK/inputs.log")"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
