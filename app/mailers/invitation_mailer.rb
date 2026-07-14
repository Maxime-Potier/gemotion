class InvitationMailer < ApplicationMailer
  def send_invitation
    @email = params[:email]
    @url = params[:url]

    I18n.with_locale(params[:locale].presence || I18n.default_locale) do
      mail(to: @email, subject: I18n.t("invitation_mailer.subject"))
    end
  end
end
