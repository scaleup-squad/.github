# compare API 응답 페이지들(jq -s 로 배열) → "이번에 나간 PR" 목록 줄.
#
# GitHub 자동 릴리스 노트(generate-notes)를 안 쓰는 이유: 흐름이 feature PR →(squash) staging →(merge commit 반영 PR) main
# 이라 main 기준 자동 노트엔 "release: staging → main" 반영 PR 만 잡힌다. 실제 기능 PR 은 커밋 제목에서 꺼낸다.
#   - squash 머지(부모 1개)    : 제목 끝 "(#N)"                        → "제목 (#N)"
#   - merge commit 머지(부모 2+): "Merge pull request #N from o/branch" → 본문 첫 줄(=PR 제목) "(#N)"
#       · branch 가 staging(반영 PR)·main(역반영) 이면 제외 — 내용이 아니라 통로다
#   - merge commit 으로 들어온 PR 안의 개별 커밋(번호 없음)·기타 직접 커밋은 제외 — 위 merge 줄이 대표한다
# 같은 PR 번호는 한 번만(처음 나온 순서 = 시간순). 본문의 "#N" 은 GitHub 이 같은 레포 PR 링크로 바꿔 준다.
[ .[].commits[]
  | (.commit.message | split("\n")) as $l
  | ([$l[1:][] | select(test("\\S"))][0] // "") as $first
  | (.parents | length) as $p
  | if $p >= 2 then
      ($l[0] | capture("^Merge pull request #(?<n>[0-9]+) from (?<b>\\S+)$")?) as $m
      | if $m == null or ($m.b | test("/(main|staging)$")) then empty
        else { n: ($m.n | tonumber), t: (if $first == "" then $m.b else $first end) } end
    else
      ($l[0] | capture("^(?<t>.*\\S)\\s*\\(#(?<n>[0-9]+)\\)$")?) as $m
      | if $m == null then empty else { n: ($m.n | tonumber), t: $m.t } end
    end
]
| reduce .[] as $x ({seen: {}, out: []};
    if .seen[$x.n | tostring] then . else .seen[$x.n | tostring] = true | .out += [$x] end)
| .out[]
| "- \(.t) (#\(.n))"
