class UserMailer < ActionMailer::Base
  default :from => "\"Satellite Deskworks\" <noreply@satellitedeskworks.com>"
  #default :from => "\"Satellite Deskworks\" <noreply@si4b.com>"

  def completion(snapshot_id)
    hash_params = {
      to:      QB_NOTIFICATION_EMAIL,
      subject: 'QB exchange is complete'
    }
    @snapshot = Snapshot.find(snapshot_id)
    mail hash_params
  end

  def failure(snapshot_id, msg)
    @error_message = msg
    hash_params = {
      to:      QB_NOTIFICATION_EMAIL,
      subject: 'QB exchange is failed'
    }
    @snapshot = Snapshot.find(snapshot_id)
    mail hash_params
  end

end
