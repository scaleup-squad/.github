# @멘션을 백틱으로 감싼다 — Release 를 발행하면 본문의 @user·@org/team 에게 알림이 간다(이메일 a@b 는 그대로).
# notes.jq(PR 제목)·release.sh(note 입력)가 함께 쓴다.
def defang_mentions: gsub("(?<![\\w`])(?<m>@[A-Za-z0-9][A-Za-z0-9-]*(/[A-Za-z0-9_.-]+)?)"; "`\(.m)`");
