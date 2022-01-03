# Slack Message


Usage:

```yaml
      - name: Slack Notification
        if: success()|| failure() || cancelled()
        uses: ./.github/actions/slack
        with:
          branch: ${{ env.BRANCH }}
          environment: ${{ env.REVIEW_APP }}
          slack_webhook_url: ${{ secrets.SLACK_WEBHOOK }}
          app_url: "${{ env.REVIEW_APP }}.${{ env.SERVER }}"
          gha_url: ${{ env.GHA_URL }}
          status: ${{ job.status }}
```