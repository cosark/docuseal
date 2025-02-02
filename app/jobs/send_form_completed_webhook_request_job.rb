# frozen_string_literal: true

class SendFormCompletedWebhookRequestJob < ApplicationJob
  USER_AGENT = 'DocuSeal.co Webhook'

  MAX_ATTEMPTS = 10

  def perform(submitter, params = {})
    attempt = params[:attempt].to_i
    config = Accounts.load_webhook_configs(submitter.submission.account)

    return if config.blank? || config.value.blank?

    Submissions::EnsureResultGenerated.call(submitter)

    ActiveStorage::Current.url_options = Docuseal.default_url_options

    resp = Faraday.post(config.value,
                        {
                          event_type: 'form.completed',
                          timestamp: Time.current,
                          data: Submitters::SerializeForWebhook.call(submitter)
                        }.to_json,
                        'Content-Type' => 'application/json',
                        'User-Agent' => USER_AGENT)

    if resp.status.to_i >= 400 && attempt <= MAX_ATTEMPTS &&
       (!Docuseal.multitenant? || submitter.account.account_configs.exists?(key: :plan))
      SendFormCompletedWebhookRequestJob.set(wait: (2**attempt).minutes)
                                        .perform_later(submitter, {
                                                         attempt: attempt + 1,
                                                         last_status: resp.status.to_i
                                                       })
    end
  end
end
