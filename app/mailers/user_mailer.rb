class UserMailer < ActionMailer::Base
  default :from => "\"Satellite Deskworks\" <noreply@satellitedeskworks.com>"

  def completion(snapshot_id)
    hash_params = {
      to:      QB_NOTIFICATIOIN_EMAIL,
      subject: 'QB exchange is complete'
    }
    @snapshot = Snapshot.find(snapshot_id)
  end

  def failure(snapshot_id, msg)
    @error_message = msg
    hash_params = {
      to:      QB_NOTIFICATIOIN_EMAIL,
      subject: 'QB exchange is failed'
    }
    @snapshot = Snapshot.find(snapshot_id)
  end

end
