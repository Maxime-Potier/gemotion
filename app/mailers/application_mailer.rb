class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAILER_FROM", ENV.fetch("GMAIL_USERNAME", "notification@gemotion.com")) }
  layout "mailer"
end
