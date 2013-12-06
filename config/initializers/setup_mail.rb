ActionMailer::Base.smtp_settings = {
  :address              => ENV['QBGW_SMTP_HOST'],      # GMAIL would be:smtp.gmail.com, Postfix: localhost
  :port                 => ENV['QBGW_SMTP_PORT'].to_i, # GMAIL would be:587, Postfix: 25
  :domain               => ENV['QBGW_MAIL_DOMAIN'],
  :user_name            => ENV['QBGW_MAIL_USER'],
  :password             => ENV['QBGW_MAIL_PASSWORD'],
  :authentication       => "plain",
  :enable_starttls_auto => true,
  :openssl_verify_mode  => 'none'
}

QB_NOTIFICATIOIN_EMAIL = ENV['QBGW_NOTIFICATIOIN_EMAIL']
