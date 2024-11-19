//// A library for interacting with the API of Clio, a law practice management 
//// platform

import gleam/http/request.{type Request}
import gleam/result
import gleam/string
import gleam/uri
import gleam/json

import glow_auth
import glow_auth/access_token as glow_access_token
import glow_auth/authorize_uri
import glow_auth/uri/uri_builder

import glio/internal/api_impure
import glio/internal/api_pure.{type MyApp}

/// Returns a MyApp record. This record is a convenient way to store your 
/// application's Clio API credentials and will need to be passed to the api
/// to obtain authorization tokens from Clio.  
pub fn build_my_app(
  my_apps_clio_id: String,
  my_apps_clio_secret: String,
  my_authorization_redirect_url: String,
) -> Result(MyApp, String) {
  use authorization_redirect_uri <- result.try(result.replace_error(
    uri.parse(my_authorization_redirect_url),
    "Your authorization redirect url could not be parsed. Is it a valid url? "
      <> " e.g. 'https://my.site.com/authorize' - you submitted: "
      <> string.inspect(my_authorization_redirect_url),
  ))
  Ok(api_pure.MyApp(
    my_apps_clio_id,
    my_apps_clio_secret,
    authorization_redirect_uri,
  ))
}

/// Generates the Clio url that the user will need to be directed to in order 
/// to log in to Clio and authorize access to your application. This is a pure
/// function. All it does is generate a url string that you will need to 
/// redirect the user to in order to authorize your application with Clio. 
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
      my_app.authorization_redirect_uri,
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
/// url returned by build_clio_authorization_url(). It sends that code to the 
/// Clio API to request a more permanent token from Clio. It then returns a 
/// either a string (which encodes the token received from Clio) or an error 
/// message. 
/// 
/// Your app will need to store the returned string somehow, such 
/// as in cookies or a database, and provide it when making api 
/// requests. 
///
/// Arguments:
/// - my_app: your application, as represented by the MyApp returned by
///   build_my_app()
/// - incoming_request: the http request made by the user after being redirected
///   from the Clio url returned by build_clio_authorization_url(). This request 
///   will have the clio authentication code in it as a parameter
pub fn fetch_authorization_token(
  my_app: MyApp,
  incoming_request: Request(a),
) -> Result(String, String) {
  use code <- result.try(api_pure.get_code_from_req(incoming_request))
  use glow_token: glow_access_token.AccessToken <- result.try(
    api_impure.fetch_glow_token_using_temporary_code(my_app, code),
  )
  use user_id <- result.try(api_impure.get_user_id_from_api(
    glow_token.access_token,
  ))
  use clio_token <- result.try(api_pure.build_clio_token_from_glow_token(
    glow_token,
    user_id,
  ))
  Ok(api_pure.convert_token_to_string(clio_token))
}

pub fn fetch_clio_data_one_page(
  stored_token: String,
  clio_api_url: String, 
  filters: Dict(String, String),
  fields_to_return: List(String),
  json_decoder: fn(String) -> Result(List(a), String)) 
-> Result(List(a), String) {
  use token <- result.try(api_pure.convert_string_to_token(stored_token))
  use base_api_request <- result.try(api.pure.url_to_request(clio_api_url))
  use api_request_with_query <- result.try(api_pure.build_api_query(
    base_api_request,
    filters,
    field_to_return
  )) 
  use api_response <- result.try(make_api_request(
    token.access_token,
    api_request_with_query))

  todo
}
