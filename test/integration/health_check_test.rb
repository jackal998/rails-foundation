# frozen_string_literal: true

require "test_helper"

# The deployed service runs an HTTP liveness probe against /up, and restarts
# the container when it stops answering. That probe lives in the platform's
# configuration, not in this repository, so nothing here would notice if the
# route were renamed or removed -- the probe would simply stop protecting
# production, silently, which is the failure mode this project keeps paying
# for. This test is where the repository holds up its half.
#
# It is deliberately not a test of Rails' health controller, which Rails
# already tests. It pins the path.
class HealthCheckTest < ActionDispatch::IntegrationTest
  test "/up answers 200 -- the production liveness probe depends on this path" do
    get "/up"

    assert_response :success
  end
end
