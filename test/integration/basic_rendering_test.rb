require "#{File.dirname(__FILE__)}/../test_helper"

class BasicRenderingTest < ActionController::IntegrationTest

  warn "Defining basic rendering tests"
  test_render "card/changes/:id"        , :users=>{ :anon=>200, :joe_user=>200 }
  test_render "card/view/:id"           , :users=>{ :anon=>200, :joe_user=>200 }, :cardtypes=>:all
  test_render "card/options/:id"        , :users=>{ :anon=>200, :joe_user=>200 }, :cardtypes=>:all
  # joe doesn't have permission to edit invitation_requests, so test edit as admin for now.
  # later should have cardtype-specific permissions settings
  test_render "card/edit/:id"           , :users=>{ :anon=>403, :admin=>200 }, :cardtypes=>:all
  test_render "card/new"                , :users=>{ :anon=>403, :joe_user=>200 }
end
