class HomeController < ApplicationController
  # The landing page is deliberately public. It also exists because the
  # generated authentication flow redirects to `root_url` after a successful
  # sign-in, so without a root route the whole login path raises NameError.
  allow_unauthenticated_access

  def index
  end
end
