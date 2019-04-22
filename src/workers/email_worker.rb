require 'sendgrid-ruby'
require 'sidekiq'

class EmailWorker
  include Sidekiq::Worker
  include SendGrid

  def perform(user_id)
    sg = SendGrid::API.new(api_key: ENV['SENDGRID_API_KEY'])
    User.where(is_admin: true, email_notifications: true, is_email_verified: true).each do |u|
      from = Email.new(email: 'noreply@wckdone.com')
      to = Email.new(email: u.email)
      subject = 'New verification request'
      content = Content.new(type: 'text/plain',
                            value: "https://wckdone.com/verifications/#{user_id}")
      mail = Mail.new(from, subject, to, content)

      sg.client.mail._('send').post(request_body: mail.to_json)
    end
  end
end

