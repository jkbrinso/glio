import gleam/uri

import gleeunit
import gleeunit/should

import glio
import glio/internal/api

pub fn main() {
  gleeunit.main()
}

pub fn build_clio_authorization_url_test() {
  let assert Ok(authorization_uri) =
    uri.parse("https://www.myapp.com/authorize")
  let my_app = glio.MyApp("MY_ID", "MY_SECRET", authorization_uri)
  glio.build_clio_authorization_url(my_app)
  |> should.equal(
    "https://app.clio.com/oauth/authorize?response_type=code&client_id=MY_ID&redirect_uri=https%3A%2F%2Fwww.myapp.com%2Fauthorize",
  )
}

pub fn token_string_conversion_test() {
  let token =
    api.ClioToken("Access token", "Refresh token", 3_141_592_654, "1234567890")
  let token_string = api.convert_token_to_string(token)

  token_string
  |> should.equal(
    "CLIO_GLEAM_TOKEN_DATA|Access token|Refresh token|3141592654|1234567890",
  )

  api.convert_string_to_token(token_string)
  |> should.equal(Ok(token))
}
