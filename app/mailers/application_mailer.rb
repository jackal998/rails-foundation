class ApplicationMailer < ActionMailer::Base
  # from@example.com is a reserved placeholder. A real provider rejects mail
  # whose From is not a domain you have verified, so shipping the placeholder
  # would have turned "we have no mail provider" into "we have one and every
  # message bounces" the moment SMTP was configured. MAIL_FROM comes from the
  # environment for the same reason the SMTP settings do: getting a domain
  # should be a deployment change, not a commit.
  default from: ENV.fetch("MAIL_FROM", "no-reply@localhost")
  layout "mailer"
end
