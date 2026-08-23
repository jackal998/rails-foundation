require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  # Both halves matter. The first proves `allow_unauthenticated_access` really
  # lets ordinary traffic through - a guard that refuses everyone looks safe
  # and takes the whole site down. The second proves the page can tell the two
  # states apart, which is the only thing making it a smoke test of the auth
  # plumbing rather than a static file.
  test "is reachable without signing in" do
    get root_url
    assert_response :success
    assert_select "a", text: "Sign in"
  end

  test "shows signed-in state once authenticated" do
    sign_in_as users(:one)
    get root_url
    assert_response :success
    assert_select "p", text: "You are signed in."
  end
end
