require "test_helper"

class InvitationMailerTest < ActionMailer::TestCase
  test "sends a localized English invitation" do
    mail = InvitationMailer.with(
      email: "invitee@example.com",
      url: "https://example.com/en/join/videos/token",
      locale: :en
    ).send_invitation

    assert_equal ["invitee@example.com"], mail.to
    expected_sender = ENV.fetch("MAILER_FROM", ENV.fetch("GMAIL_USERNAME", "notification@gemotion.com"))
    assert_equal [expected_sender], mail.from
    assert_equal "You are invited to participate in a GeMotion video", mail.subject
    assert_match "Join the project", mail.html_part.body.to_s
    assert_match "https://example.com/en/join/videos/token", mail.text_part.body.to_s
  end

  test "sends a localized French invitation" do
    mail = InvitationMailer.with(
      email: "invitee@example.com",
      url: "https://example.com/fr/join/videos/token",
      locale: :fr
    ).send_invitation

    assert_equal "Invitation à participer à une vidéo GeMotion", mail.subject
    assert_match "Participer au projet", mail.html_part.body.to_s
  end
end
