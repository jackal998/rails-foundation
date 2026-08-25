require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_password_path
    assert_response :success
  end

  test "create" do
    post passwords_path, params: { email_address: @user.email_address }
    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "create for an unknown user redirects but sends no mail" do
    post passwords_path, params: { email_address: "missing-user@example.com" }
    assert_enqueued_emails 0
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "edit" do
    get edit_password_path(@user.password_reset_token)
    assert_response :success
  end

  test "edit with invalid password reset token" do
    get edit_password_path("invalid token")
    assert_redirected_to new_password_path

    follow_redirect!
    assert_notice "reset link is invalid"
  end

  test "update" do
    assert_changes -> { @user.reload.password_digest } do
      put password_path(@user.password_reset_token), params: { password: "new", password_confirmation: "new" }
      assert_redirected_to new_session_path
    end

    follow_redirect!
    assert_notice "Password has been reset"
  end

  test "update with non matching passwords" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "no", password_confirmation: "match" }
      assert_redirected_to edit_password_path(token)
    end

    follow_redirect!
    assert_notice "doesn.t match"
  end

  # params.permit returns an empty hash when the form arrives with no password
  # in it, and update({}) succeeds against an otherwise valid record. The
  # generated controller therefore destroyed every session and announced a
  # successful reset while the old password still worked -- the worst possible
  # outcome for someone rotating a password they believe is compromised.
  test "update with a blank password changes nothing and says so" do
    token = @user.password_reset_token
    session = @user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")

    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token)
      assert_redirected_to edit_password_path(token)
    end

    assert Session.exists?(session.id), "the reset failed, so the sessions must survive it"

    follow_redirect!
    assert_notice "can.t be blank"
  end

  # The first fix checked params[:password], which an Array satisfies: it is
  # not blank, so it passed the guard, and then permit discarded it for not
  # being a scalar -- leaving update({}) to succeed exactly as before. Found by
  # an external review of the fix, not by the tests written alongside it.
  test "update with an array-shaped password changes nothing and says so" do
    token = @user.password_reset_token
    session = @user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")

    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: [ "x" ], password_confirmation: [ "x" ] }
      assert_redirected_to edit_password_path(token)
    end

    assert Session.exists?(session.id), "the reset failed, so the sessions must survive it"

    follow_redirect!
    assert_notice "can.t be blank"
  end

  # bcrypt refuses anything over 72 bytes, which forty accented characters
  # reach. Reporting that as "Passwords did not match" sends the user round the
  # same loop forever, retyping two values that match perfectly.
  test "update with an over-long password explains the real reason" do
    token = @user.password_reset_token
    too_long = "é" * 40

    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: too_long, password_confirmation: too_long }
      assert_redirected_to edit_password_path(token)
    end

    follow_redirect!
    assert_notice "too long"
  end

  private
    def assert_notice(text)
      assert_select "div", /#{text}/
    end
end
