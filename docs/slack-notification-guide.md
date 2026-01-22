# Slack 알림 연동 가이드

GitHub Actions 배포 결과를 Slack으로 알림 받는 방법입니다.

## 목차

- [사전 준비](#사전-준비)
- [Slack Webhook 설정](#slack-webhook-설정)
- [GitHub Secrets 설정](#github-secrets-설정)
- [워크플로우 수정](#워크플로우-수정)

---

## 사전 준비

- Slack 워크스페이스 관리자 권한
- GitHub 레포지토리 Settings 접근 권한

---

## Slack Webhook 설정

### 1. Slack App 생성

1. https://api.slack.com/apps 접속
2. "Create New App" 클릭
3. "From scratch" 선택
4. App Name: `GitHub Deploy Bot`
5. Workspace 선택 후 생성

### 2. Incoming Webhooks 활성화

1. 좌측 메뉴 "Incoming Webhooks" 클릭
2. "Activate Incoming Webhooks" 토글 ON
3. "Add New Webhook to Workspace" 클릭
4. 알림 받을 채널 선택 (예: #deployments)
5. "Allow" 클릭

### 3. Webhook URL 복사

생성된 Webhook URL을 복사합니다. (형식: `https://hooks.slack.com/services/...`)

---

## GitHub Secrets 설정

각 레포지토리에 Secret 추가:

1. Repository > Settings > Secrets and variables > Actions
2. "New repository secret" 클릭
3. Name: `SLACK_WEBHOOK_URL`
4. Secret: 위에서 복사한 Webhook URL

---

## 워크플로우 수정

### Frontend (Dashboard)

`.github/workflows/vercel-deploy.yml` 수정:

```yaml
      - name: Summary
        if: success()
        run: |
          {
            echo "### ✅ Vercel Deploy"
            echo "- Branch: ${{ github.ref_name }}"
            echo "- Commit: ${{ github.sha }}"
            echo "- Environment: ${DEPLOY_ENV}"
            echo "- URL: ${DEPLOY_URL}"
          } >> "$GITHUB_STEP_SUMMARY"

      # 아래 내용 추가
      - name: Slack Notification (Success)
        if: success()
        uses: slackapi/slack-github-action@v2.0.0
        with:
          webhook: ${{ secrets.SLACK_WEBHOOK_URL }}
          webhook-type: incoming-webhook
          payload: |
            {
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "✅ *Deploy Success*\n*Repository:* ${{ github.repository }}\n*Branch:* ${{ github.ref_name }} → ${DEPLOY_ENV}\n*URL:* ${DEPLOY_URL}\n*Commit:* ${{ github.event.head_commit.message }}"
                  }
                }
              ]
            }

      - name: Slack Notification (Failure)
        if: failure()
        uses: slackapi/slack-github-action@v2.0.0
        with:
          webhook: ${{ secrets.SLACK_WEBHOOK_URL }}
          webhook-type: incoming-webhook
          payload: |
            {
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "❌ *Deploy Failed*\n*Repository:* ${{ github.repository }}\n*Branch:* ${{ github.ref_name }}\n*Link:* ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
                  }
                }
              ]
            }
```

### Backend

`.github/workflows/deploy.yml` 각 deploy job 끝에 동일하게 추가

---

## 알림 채널 분리 (선택)

환경별로 다른 채널에 알림:

| 환경 | 채널 | Secret |
|------|------|--------|
| Production | #prod-deploys | `SLACK_WEBHOOK_PROD` |
| Staging | #staging-deploys | `SLACK_WEBHOOK_STAGE` |
| Development | #dev-deploys | `SLACK_WEBHOOK_DEV` |

---

## 테스트

설정 후 빈 커밋으로 테스트:

```bash
git commit --allow-empty -m "test: Slack notification test"
git push origin main
```

---

**문서 버전**: 1.0
**최종 수정**: 2026-01-22
