import gleam/uri

import gleeunit
import gleeunit/should

import clio_gleam

pub fn main() {
  gleeunit.main()
}

// gleeunit test functions end in `_test`
pub fn build_clio_authorization_url_test() {
  let assert Ok(authorization_uri) =
    uri.parse("https://www.myapp.com/authorize")
  let my_app = clio_gleam.MyApp("MY_ID", "MY_SECRET", authorization_uri)
  clio_gleam.build_clio_authorization_url(my_app)
  |> should.equal(
    "https://app.clio.com/oauth/authorize?response_type=code&client_id=MY_ID&redirect_uri=https%3A%2F%2Fwww.myapp.com%2Fauthorize",
  )
}
