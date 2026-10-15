#!/usr/bin/env bash
# prod 배포 버전 이름을 배포 "전에" 정한다(gos-harness #95).
# 앱은 배포 시점에 자기 버전을 알아야 /health 에 보여줄 수 있는데, 태그는 배포·스모크가 성공한 뒤에야 만든다.
# 그래서 이름만 먼저 계산하고(읽기 전용) 실물(태그·Release)은 prod-version-release 가 성공 후에 만든다.
# 배포가 실패하면 이 이름은 버려지고, 다음 배포가 같은 N 을 다시 계산한다 — 번호에 구멍이 안 생긴다.
#
# 입력(env): GH_TOKEN(contents: read), REPO(owner/name), SHA(40자리 커밋)
# 출력: GITHUB_OUTPUT 이 있으면 거기에, 없으면(로컬) stdout 에 key=value
#   version     — mode=new 면 새 이름, redeploy 면 sha 에 정확히 붙은 태그(없으면 빈 값)
#   commit      — sha 앞 7자리
#   deployed-at — ISO-8601 UTC (계획 시점 = 배포 직전)
#   mode        — new | redeploy
#   previous-tag— 지금 있는 가장 최신 v* 태그(없으면 빈 값)
#   memo-tag    — redeploy 때 메모를 덧붙일 Release 의 태그
#
# 테스트용 env: PV_TODAY(YYYY.MM.DD) — KST 오늘 날짜를 고정한다
set -euo pipefail

# 형식을 정확히 맞춘 태그만 — v2026.10.15 · v1.2.3 · v2026.10.15.3-rc 같은 것은 버전 계산에 끼지 않는다.
# N 은 0 으로 시작하지 않는다(.03 과 .3 이 같은 번호로 섞이지 않게).
TAG_RE='^v[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[1-9][0-9]*$'

# stdin 태그 이름 → 형식에 맞는 것만 버전 오름차순.
# 사전순 정렬은 .10 이 .9 앞에 와서 틀린다 — 날짜 세 칸과 N 을 각각 숫자로 정렬한다.
sort_tags() {
  { grep -E "$TAG_RE" || true; } | sort -t. -k1,1 -k2,2n -k3,3n -k4,4n -u
}

# $1=오늘(YYYY.MM.DD), stdin=태그 이름 → 오늘 쓸 다음 버전. 다른 날짜 태그는 N 에 영향 없다(날마다 1부터).
next_version() {
  local today=$1 max
  max=$(sort_tags | awk -F. -v d="v$today" '($1 "." $2 "." $3) == d { n = $4 + 0; if (n > m) m = n } END { print m + 0 }')
  echo "v$today.$((max + 1))"
}

# compare(latest...sha) 결과 → mode. 판단만 하고 이름은 호출부가 채운다.
#   ahead     = 마지막 배포 이후 새 커밋 → 새 버전
#   identical = 같은 커밋 재배포, behind = 예전 커밋으로 롤백 → 새 태그 없이 기존 Release 에 메모
#   diverged  = 최신 태그가 main 이력 밖(강제 푸시 등) — 롤백도 아니니 새 버전으로 보되 경고
#   (없음)    = 태그가 하나도 없는 첫 배포 → 새 버전
decide_mode() {
  case "$1" in
    ''|ahead) echo new ;;
    identical|behind) echo redeploy ;;
    diverged)
      echo "::warning::최신 태그가 배포 커밋과 갈라져 있다(diverged) — 새 버전으로 처리한다. 강제 푸시·태그 오기입 여부 확인" >&2
      echo new ;;
    *) echo "::error::알 수 없는 compare status: $1" >&2; return 1 ;;
  esac
}

# 태그 ref 목록(tsv: name type objsha) 에서 sha 를 정확히 가리키는 것 중 가장 높은 버전.
# 사람이 `git tag -a` 로 단 기준 태그는 annotated 라 객체 sha 가 커밋이 아니다 — 한 번 더 따라간다.
exact_tag() {
  local sha=$1 name type obj commit
  while IFS=$'\t' read -r name type obj; do
    [ -n "$name" ] || continue
    commit=$obj
    if [ "$type" = tag ]; then
      commit=$(gh api "repos/$REPO/git/tags/$obj" --jq .object.sha)
    fi
    if [ "$commit" = "$sha" ]; then echo "$name"; fi
  done | sort_tags | tail -n 1
}

emit() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "$1=$2" >> "$GITHUB_OUTPUT"; fi
  echo "$1=$2"
}

main() {
  : "${REPO:?REPO 필요(owner/name)}"
  : "${SHA:?SHA 필요}"
  if ! [[ "$SHA" =~ ^[0-9a-f]{40}$ ]]; then
    echo "::error::sha 는 40자리 커밋 해시여야 한다(브랜치 이름 X): $SHA" >&2
    return 1
  fi

  local refs names latest status="" mode version="" memo="" today
  # matching-refs 는 접두어 일치라 v 로 시작하는 다른 태그도 오지만 형식 필터에서 걸러진다
  refs=$(gh api --paginate "repos/$REPO/git/matching-refs/tags/v" \
    --jq '.[] | [(.ref | ltrimstr("refs/tags/")), .object.type, .object.sha] | @tsv')
  refs=$(printf '%s\n' "$refs" | awk -F'\t' -v re="$TAG_RE" '$1 ~ re')
  names=$(printf '%s\n' "$refs" | cut -f1)
  latest=$(printf '%s\n' "$names" | sort_tags | tail -n 1)

  if [ -n "$latest" ]; then
    # 실패(404 등)는 그대로 실패 — 잘못된 이름으로 배포하느니 멈춘다
    status=$(gh api "repos/$REPO/compare/refs/tags/$latest...$SHA" --jq .status)
  fi
  mode=$(decide_mode "$status")

  if [ "$mode" = new ]; then
    today=${PV_TODAY:-$(TZ=Asia/Seoul date +%Y.%m.%d)}
    version=$(printf '%s\n' "$names" | next_version "$today")
  else
    version=$(printf '%s\n' "$refs" | exact_tag "$SHA")
    memo=${version:-$latest}
  fi

  echo "latest-tag=${latest:-(없음)} compare=${status:-(태그 없음)}" >&2
  emit version "$version"
  emit commit "${SHA:0:7}"
  emit deployed-at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  emit mode "$mode"
  emit previous-tag "$latest"
  emit memo-tag "$memo"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
