//// This is the top of the main clio_gleam.gleam file

import gleam/dict
import gleam/http/request.{type Request}
import gleam/http/response
import gleam/httpc
import gleam/result
import gleam/string
import gleam/uri.{type Uri}

import glow_auth
import glow_auth/access_token
import glow_auth/authorize_uri
import glow_auth/token_request
import glow_auth/uri/uri_builder

/// Holds unique details concerning your application. 
///
/// - authorization_uri: In the OAuth2 workflow, this is the url that Clio
/// will send your users back to after they provide their credentials to
/// Clio and authorize your application
///
/// Note: authorization_uri cannot be localhost. For development purposes, you
/// should use, e.g., 127.0.0.1. If you are using mist, you can use 
/// mist.bind("127.0.0.1") in your handler pipe before starting your server to 
/// do this
pub type MyApp {
  MyApp(id: String, secret: String, authorization_uri: Uri)
}

pub type ClioToken =
  access_token.AccessToken

/// Generates the Clio url that the user will need to be directed to in order 
/// to log in to Clio and authorize access to your application. This is a pure
/// function. All it does is generate a url string that you will need to 
/// redirect the user to. 
///
/// At the moment, does not use either of these two optioonal parameters exposed 
/// by the Clio api:
///  - state: An opaque value used to maintain state between the request and the 
///    callback (i.e., a CSRF token)
///  - redirect_on_decline: When set to "true", redirects users to the provided 
///    redirect_uri when a user declines the app permissions; defaults to "false".
pub fn build_clio_authorization_url(my_app: MyApp) -> String {
  let assert Ok(clio_uri) = uri.parse("https://app.clio.com")
  let client = glow_auth.Client(my_app.id, my_app.secret, clio_uri)
  let clio_auth_uri_appendage = uri_builder.RelativePath("oauth/authorize")
  let auth_uri_spec =
    authorize_uri.build(
      client,
      clio_auth_uri_appendage,
      my_app.authorization_uri,
    )
  let auth_uri = authorize_uri.to_code_authorization_uri(auth_uri_spec)
  uri.to_string(auth_uri)
}

/// After using the authorization url to get a code from Clio, this function
/// should be called server-side to obtain a secure authorization token from 
/// Clio that will be used to authenticate the application with Clio in each 
/// API request. 
///
/// This function uses the code received from Clio when the user visits the
/// build_clio_authorization() url. It sends that code to the Clio API to 
/// request a more permanent token from Clio. It then returns that token.
///
/// Arguments:
/// - app: your application, as represented in an instance of type MyApp
/// - incoming_req: the http request made by the user after being redirected
///   from Clio. This request will have the clio authentication code in it
pub fn authorize(
  my_app: MyApp,
  incoming_req: Request(String),
) -> Result(ClioToken, String) {
  use code <- result.try(get_code_from_req(incoming_req))
  get_token_from_code(my_app, code, my_app.authorization_uri)
}

/// Given a Request req, returns the value of the query parameter "code"
/// included in the request.
fn get_code_from_req(req: Request(String)) -> Result(String, String) {
  let code_result = {
    use queries_list <- result.try(request.get_query(req))
    let queries_dict = dict.from_list(queries_list)
    dict.get(queries_dict, "code")
  }
  case code_result {
    Ok(val) -> Ok(val)
    Error(e) -> Error("The user's request did not contain an authorization 
      code. This could occur if the user was not re-directed here directly
      from Clio. More information " <> string.inspect(e))
  }
}

/// Using a given temporary code from clio from the authorization step,
/// attempts to fetch a more permanent authorization token and refresh token
/// directly from clio
fn get_token_from_code(
  my_app: MyApp,
  code: String,
  redirect_uri: uri.Uri,
) -> Result(access_token.AccessToken, String) {
  let assert Ok(clio_uri) = uri.parse("https://app.clio.com")
  let client = glow_auth.Client(my_app.id, my_app.secret, clio_uri)
  let token_uri_appendage = uri_builder.RelativePath("oauth/token")
  let auth_code_req =
    token_request.authorization_code(
      client,
      token_uri_appendage,
      code,
      redirect_uri,
    )
  case httpc.send(auth_code_req) {
    Ok(resp) -> decode_token_from_response(resp)
    Error(e) -> Error("Failed to receive a response from Clio when attempting
      to get authorization token. More information: " <> string.inspect(e))
  }
}

/// Helper function for above
fn decode_token_from_response(
  resp: response.Response(String),
) -> Result(access_token.AccessToken, String) {
  case access_token.decode_token_from_response(resp.body) {
    Ok(token) -> Ok(token)
    Error(e) -> Error("Unable to decode access token from the response
      received from Clio. More information: " <> string.inspect(e))
  }
}
