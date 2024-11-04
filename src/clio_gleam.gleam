/// This is the top of the main clio_gleam.gleam file
import gleam/uri.{type Uri}

import glow_auth/uri/uri_builder
import glow_auth
import glow_auth/authorize_uri

pub type MyApp {
  MyApp(id: String, 
    secret: String,
    authorization_uri: Uri
    )
}

// Generates the Clio url that the user will need to be directed to in order 
// to log in to Clio and authorize access to your application. 
//
// At the moment, does not use either of these two optioonal parameters exposed 
// by the Clio api:
//  - state: An opaque value used to maintain state between the request and the 
//    callback (i.e., a CSRF token)
//  - redirect_on_decline: When set to "true", redirects users to the provided 
//    redirect_uri when a user declines the app permissions; defaults to "false".
pub fn build_clio_authorization_url(app: MyApp) -> String {
  let assert Ok(clio_uri) = uri.parse("https://app.clio.com")
  let client = glow_auth.Client(app.id, app.secret, clio_uri)
  let clio_auth_uri_appendage = uri_builder.RelativePath("oauth/authorize")
  let auth_uri_spec =
    authorize_uri.build(client, clio_auth_uri_appendage, app.authorization_uri)
  let auth_uri = authorize_uri.to_code_authorization_uri(auth_uri_spec)
  uri.to_string(auth_uri)
}