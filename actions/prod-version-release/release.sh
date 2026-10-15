#!/usr/bin/env bash
# prod 배포·스모크 성공 "후" 버전을 실물로 만든다(gos-harness #95) — prod-version-plan 이 미리 정한 이름 그대로.
#   mode=new      : 태그(ref) 생성 → Release 생성(이전 태그 이후 나간 PR 목록) → Slack
#   mode=redeploy : 새 태그 없음. memo-tag 의 Release "배포 기록" 에 한 줄 추가 → Slack
# 태그·Release 실패는 스텝을 빨갛게 끝낸다(배포는 이미 됐다 — 빨간불이 "버전 기록이 빠졌다" 는 신호).
# Slack 실패는 경고만 — 알림 때문에 배포 런이 빨개지면 안 된다.
#
# 입력(env): GH_TOKEN(contents: write) REPO SHA(40자리) VERSION MODE PREVIOUS_TAG MEMO_TAG
#            SERVICE NOTE RUN_URL SLACK_TOKEN SLACK_CHANNEL
#            DRY_RUN=1 이면 읽기만 하고 쓰기(태그·Release·Slack)는 내용만 출력한다
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# 태그 형식(TAG_RE)·정렬(sort_tags)·목록(tag_refs)은 plan 과 한 벌 — 같은 레포 체크아웃 안이라 상대 경로로 닿는다
# shellcheck source=SCRIPTDIR/../prod-version-plan/plan.sh
source "$HERE/../prod-version-plan/plan.sh"
DRY_RUN=${DRY_RUN:-}
TMP=${RUNNER_TEMP:-${TMPDIR:-/tmp}}

kst_now() { TZ=Asia/Seoul date '+%Y-%m-%d %H:%M KST'; }

# 쓰기 API — DRY_RUN 이면 호출 대신 무엇을 보낼지 출력
write_api() {
  if [ -n "$DRY_RUN" ]; then
    echo "[dry-run] gh api $*" >&2
    # 본문(JSON)은 줄바꿈을 살려 사람이 읽을 수 있게 키별로
    [ -t 0 ] || jq -r 'to_entries[] | "\(.key): \(.value)"' | sed 's/^/[dry-run]   /' >&2
    echo "(dry-run)"
    return 0
  fi
  gh api "$@"
}

# 태그 → 그 태그가 가리키는 커밋 sha(없으면 빈 값). annotated 태그(사람이 단 기준 태그)는 한 번 더 따라간다.
tag_commit() {
  local out type obj
  out=$(gh api "repos/$REPO/git/ref/tags/$1" --jq '[.object.type, .object.sha] | @tsv' 2>/dev/null) || return 0
  IFS=$'\t' read -r type obj <<< "$out"
  if [ "$type" = tag ]; then gh api "repos/$REPO/git/tags/$obj" --jq .object.sha; else echo "$obj"; fi
}

# 태그 생성. 이미 있으면(422) 가리키는 커밋으로 판단한다:
#   같은 커밋 = 같은 배포의 재실행(re-run) — 이미 된 일이니 통과하고 Release 단계로 간다
#   다른 커밋 = 동시 배포가 같은 N 을 먼저 가져감 — 실패. 이 배포의 /health 는 이미 이 이름을 달고 떴으니
#              N 을 몰래 올려 태그를 만들면 /health 와 태그가 어긋난다. 빨간불로 사람에게 넘긴다
#              (호출 측 prod 배포 잡에 concurrency 그룹이 있으면 생기지 않는다)
create_tag() {
  local err existing
  err="$TMP/pv-tag-err.txt"
  if write_api -X POST "repos/$REPO/git/refs" -f "ref=refs/tags/$VERSION" -f "sha=$SHA" < /dev/null > /dev/null 2> "$err"; then
    [ -n "$DRY_RUN" ] && cat "$err" >&2
    echo "태그 생성: $VERSION → ${SHA:0:7}"
    return 0
  fi
  existing=$(tag_commit "$VERSION")
  if [ "$existing" = "$SHA" ]; then
    echo "::notice::태그 $VERSION 가 이미 같은 커밋에 있다(재실행) — 그대로 쓴다"
    return 0
  fi
  cat "$err" >&2
  if [ -n "$existing" ]; then
    echo "::error::태그 $VERSION 가 이미 다른 커밋(${existing:0:7})에 있다 — 동시 배포 의심. 이 배포(${SHA:0:7})의 /health 버전과 태그가 어긋났으니 사람이 정리할 것" >&2
  else
    echo "::error::태그 $VERSION 생성 실패" >&2
  fi
  return 1
}

# Release JSON(없으면 빈 값). 404 외 오류는 그대로 실패
get_release() {
  local out
  if out=$(gh api "repos/$REPO/releases/tags/$1" 2>&1); then echo "$out"; return 0; fi
  if grep -q 'HTTP 404' <<< "$out"; then return 0; fi
  echo "$out" >&2
  return 1
}

# $1=tag $2=body파일 $3=make_latest(true|false)
create_release() {
  jq -n --arg tag "$1" --rawfile body "$2" --arg latest "$3" \
    '{tag_name: $tag, name: $tag, body: $body, make_latest: $latest}' \
    | write_api -X POST "repos/$REPO/releases" --input - --jq .html_url
}

# 이전 태그 이후 나간 PR 목록. compare 는 페이지당 최대 100 커밋 — 끝까지 넘겨 받는다.
# GitHub 문서상 compare 의 커밋 목록은 상한이 있을 수 있어(대략 250~수천) 받은 수 < total_commits 면 잘렸다고 밝힌다.
# (일 1~수회 배포라 실제로는 수십 커밋 — 상한에 닿는 건 기준 태그가 아주 오래됐을 때뿐)
render_changes() { # $1=이전 태그
  local pages total got
  pages="$TMP/pv-compare.json"
  gh api --paginate "repos/$REPO/compare/refs/tags/$1...$SHA?per_page=100" > "$pages"
  total=$(jq -s '.[0].total_commits' "$pages")
  got=$(jq -s '[.[].commits[]] | length' "$pages")
  local list
  list=$(jq -rs -f "$HERE/notes.jq" "$pages")
  if [ -n "$list" ]; then echo "$list"; else echo "- (PR 번호가 붙은 커밋 없음 — 아래 비교 링크에서 커밋 확인)"; fi
  if [ "$got" -lt "$total" ]; then
    echo
    echo "⚠️ 커밋 ${total}개 중 ${got}개만 받아 목록이 잘렸다 — 전체는 비교 링크에서."
  fi
}

# 버전 Release 본문. $1=이 버전 태그 $2=바로 앞 태그(없으면 빈 값) $3=배포 기록 첫 줄 이름
new_body() {
  local server=${GITHUB_SERVER_URL:-https://github.com}
  echo "**${SERVICE}** prod 배포 — \`${SHA:0:7}\`"
  echo
  if [ -n "$2" ]; then
    echo "## 포함된 변경 ($2 이후)"
    render_changes "$2"
    echo
    echo "비교: ${server}/${REPO}/compare/$2...$1"
  else
    echo "## 포함된 변경"
    echo "- 이전 버전 태그가 없어 목록을 만들 수 없다(이 레포의 첫 버전 태그). 기준 태그를 먼저 달면 다음부터 나온다."
  fi
  echo
  echo "## 배포 기록"
  echo "- $(kst_now) $3: \`${SHA:0:7}\`${NOTE:+ (${NOTE})} [run](${RUN_URL})"
}

# 형식 맞는 태그 중 $1 바로 앞 버전(없으면 빈 값)
tag_before() {
  tag_refs | cut -f1 | sort_tags | awk -v t="$1" '$0 == t { print p; exit } { p = $0 }'
}

do_new() {
  create_tag
  local rel body url
  rel=$(get_release "$VERSION")
  if [ -n "$rel" ]; then
    # 재실행으로 Release 까지 이미 있다 — 덮어쓰지 않는다(그 사이 추가된 메모를 지우지 않게)
    url=$(jq -r .html_url <<< "$rel")
    echo "::notice::Release $VERSION 가 이미 있다 — 그대로 둔다: $url"
  else
    body="$TMP/pv-body.md"
    new_body "$VERSION" "$PREVIOUS_TAG" 배포 > "$body"
    url=$(create_release "$VERSION" "$body" true < /dev/null)
    echo "Release 생성: $url"
  fi
  RELEASE_URL=$url
  SLACK_TEXT=":rocket: *${SERVICE}* prod 배포 완료 — *${VERSION}* (\`${SHA:0:7}\`)${NOTE:+ · ${NOTE}}"
}

do_redeploy() {
  if [ -z "$MEMO_TAG" ]; then
    echo "::warning::redeploy 인데 memo-tag 가 비었다 — 기록할 Release 가 없어 건너뛴다"
    SLACK_TEXT=""
    return 0
  fi
  # 같은 커밋 재배포(정확히 붙은 태그가 최신) vs 예전 커밋으로 되돌림
  local kind=롤백
  [ -n "$VERSION" ] && [ "$VERSION" = "$PREVIOUS_TAG" ] && kind=재배포
  local line rel id body url prev latest=false
  line="- $(kst_now) ${kind}: \`${SHA:0:7}\`${NOTE:+ (${NOTE})} [run](${RUN_URL})"
  rel=$(get_release "$MEMO_TAG")
  if [ -z "$rel" ]; then
    # 태그는 있는데 Release 가 없다 — 두 경우:
    #  ① 재실행 보완: 1차 런이 태그까지 만들고 Release/compare 에서 실패 → "Re-run jobs" 하면 plan 은 그 태그를 보고
    #     redeploy 라고 판단한다. 여기서 원래 했어야 할 일(PR 목록 Release + :rocket: 알림)을 마저 한다.
    #  ② 사람이 단 기준 태그(앞 태그 없음) — 목록을 만들 수 없으니 최소 Release 에 기록만.
    # 둘의 구분 = MEMO_TAG 앞에 형식 맞는 태그가 있는가. 최신 태그일 때만 Latest(예전 태그 롤백이 Latest 로 뜨면 오해)
    [ "$MEMO_TAG" = "$PREVIOUS_TAG" ] && latest=true
    prev=$(tag_before "$MEMO_TAG")
    body="$TMP/pv-body.md"
    if [ -n "$prev" ]; then
      if [ "$kind" = 재배포 ]; then
        new_body "$MEMO_TAG" "$prev" "배포(재실행 — Release 보완)" > "$body"
      else
        # 예전 태그로 롤백했는데 그 Release 가 빠져 있었다 — 목록은 채우고 기록은 롤백으로
        { new_body "$MEMO_TAG" "$prev" "배포(Release 보완 — 원 배포 시각 아님)"; echo "$line"; } > "$body"
      fi
      url=$(create_release "$MEMO_TAG" "$body" "$latest" < /dev/null)
      echo "Release 없음(앞 태그 $prev 있음) → 재실행 보완으로 전체 Release 생성: $url"
      RELEASE_URL=$url
      if [ "$kind" = 재배포 ]; then
        SLACK_TEXT=":rocket: *${SERVICE}* prod 배포 완료 — *${MEMO_TAG}* (\`${SHA:0:7}\`)${NOTE:+ · ${NOTE}}"
      else
        SLACK_TEXT=":repeat: *${SERVICE}* prod ${kind} — \`${SHA:0:7}\` (${MEMO_TAG})${NOTE:+ · ${NOTE}}"
      fi
      return 0
    fi
    { echo "기준 태그 — 자동 Release 이전에 달린 태그라 변경 목록이 없다."
      echo
      echo "## 배포 기록"
      echo "$line"; } > "$body"
    url=$(create_release "$MEMO_TAG" "$body" "$latest" < /dev/null)
    echo "Release 없음 → 최소 Release 생성: $url"
  else
    id=$(jq -r .id <<< "$rel")
    url=$(jq -r .html_url <<< "$rel")
    body=$(jq -r '.body // ""' <<< "$rel")
    # 사람이 손으로 만든 Release 면 기록 구역이 없을 수 있다 — 그때만 제목을 붙인다
    if ! grep -q '^## 배포 기록' <<< "$body"; then body=$(printf '%s\n\n## 배포 기록' "$body"); fi
    body=$(printf '%s\n%s' "$body" "$line")
    jq -n --arg body "$body" '{body: $body}' \
      | write_api -X PATCH "repos/$REPO/releases/$id" --input - --jq .html_url > /dev/null
    echo "Release $MEMO_TAG 에 기록: $line"
  fi
  RELEASE_URL=$url
  SLACK_TEXT=":repeat: *${SERVICE}* prod ${kind} — \`${SHA:0:7}\` (${VERSION:-미태그 커밋 · 기록은 ${MEMO_TAG}})${NOTE:+ · ${NOTE}}"
}

notify_slack() {
  [ -n "$SLACK_TEXT" ] || return 0
  if [ -z "${SLACK_TOKEN:-}" ] || [ -z "${SLACK_CHANNEL:-}" ]; then
    echo "::notice::slack-token·slack-channel 이 없어 Slack 알림은 건너뛴다"
    return 0
  fi
  local payload resp
  payload=$(jq -n --arg c "$SLACK_CHANNEL" --arg t "$SLACK_TEXT"$'\n'"<${RELEASE_URL}|Release 보기>" \
    '{channel: $c, text: $t, unfurl_links: false}')
  if [ -n "$DRY_RUN" ]; then echo "[dry-run] slack chat.postMessage $payload" >&2; return 0; fi
  if ! resp=$(curl -sS --max-time 10 -X POST https://slack.com/api/chat.postMessage \
      -H "Authorization: Bearer $SLACK_TOKEN" -H 'Content-Type: application/json; charset=utf-8' \
      --data "$payload" 2>&1); then
    echo "::warning::Slack 전송 실패(네트워크): $resp"
    return 0
  fi
  if [ "$(jq -r '.ok // false' <<< "$resp" 2>/dev/null)" != true ]; then
    echo "::warning::Slack 전송 실패: $(jq -r '.error // .' <<< "$resp" 2>/dev/null || echo "$resp")"
  fi
  return 0
}

main() {
  : "${REPO:?}" "${SHA:?}" "${MODE:?}" "${SERVICE:?service 필요}" "${RUN_URL:?}"
  VERSION=${VERSION:-} PREVIOUS_TAG=${PREVIOUS_TAG:-} MEMO_TAG=${MEMO_TAG:-} NOTE=${NOTE:-}
  if ! [[ "$SHA" =~ ^[0-9a-f]{40}$ ]]; then
    echo "::error::sha 는 40자리 커밋 해시여야 한다: $SHA" >&2
    return 1
  fi
  # plan 출력을 잘못 배선하면(오타·다른 스텝 id) 엉뚱한 이름으로 태그가 생긴다 — 형식부터 막는다
  local v
  for v in "VERSION=$VERSION" "PREVIOUS_TAG=$PREVIOUS_TAG" "MEMO_TAG=$MEMO_TAG"; do
    if [ -n "${v#*=}" ] && ! grep -qE "$TAG_RE" <<< "${v#*=}"; then
      echo "::error::${v%%=*} 가 버전 형식(vYYYY.MM.DD.N)이 아니다: ${v#*=}" >&2
      return 1
    fi
  done
  if [ "$MODE" = new ] && [ -z "$VERSION" ]; then
    echo "::error::mode=new 인데 version 이 비었다 — plan 출력 배선 확인" >&2
    return 1
  fi
  RELEASE_URL="" SLACK_TEXT=""
  case "$MODE" in
    new) do_new ;;
    redeploy) do_redeploy ;;
    *) echo "::error::mode 는 new|redeploy: $MODE" >&2; return 1 ;;
  esac
  notify_slack
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
