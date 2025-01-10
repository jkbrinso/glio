//// A library for interacting with the API of Clio, a law practice management 
//// platform

import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/http/request.{type Request}
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri
import glio/internal/api_impure
import glio/internal/api_pure.{
  type ApiResponse, type ClioPagesUrls, TokenNotRenewed, TokenRenewed,
}
import glow_auth
import glow_auth/access_token as glow_access_token
import glow_auth/authorize_uri
import glow_auth/uri/uri_builder

pub type ClioToken =
  api_pure.ClioToken

pub type MyApp =
  api_pure.MyApp

pub type ClioYielder(a) {
  ClioYielder(
    data: List(a),
    prev: Option(fn() -> Result(ClioYielder(a), String)),
    next: Option(fn() -> Result(ClioYielder(a), String)),
  )
}

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
) -> Result(ApiResponse(String), String) {
  use code <- result.try(api_pure.get_code_from_req(incoming_request))
  use glow_token: glow_access_token.AccessToken <- result.try(
    api_impure.fetch_glow_token_using_temporary_code(my_app, code),
  )
  let assert Ok(temp_token) =
    api_pure.build_clio_token_from_glow_token(glow_token, "0")
  case api_impure.get_user_id_from_api(temp_token) {
    Ok(TokenNotRenewed(user_id)) -> {
      use clio_token <- result.try(api_pure.build_clio_token_from_glow_token(
        glow_token,
        user_id,
      ))
      Ok(TokenNotRenewed(api_pure.convert_token_to_string(clio_token)))
    }
    Ok(TokenRenewed(user_id, new_token)) ->
      Error(
        "fetch_authorization_token() should not get to this branch
      because it is an initial authorization and can't be expired yet.",
      )

    Error(message) -> Error("fetch_authorization_token() failed -> " <> message)
  }
}

/// Gets one page of data from clio, with next and previous urls. Useful if
/// your want to use a json decoder that does not return 
/// Result(List(a), String) or if you want to handle subsequent previous/next
/// page requests in a more sophisticated way than fetch 
///
/// Returns a tuple of the form:
///    #(your json_decoder return value, previous_url, next_url)
///
/// Otherwise, use fetch_yielder or fetch_all_pages
pub fn fetch_one_previous_next(
  token: ClioToken,
  clio_api_url: String,
  filters: Dict(String, String),
  json_decoder: fn(String) -> Result(List(a), String),
  fields_to_return: List(String),
) -> Result(ApiResponse(#(List(a), ClioPagesUrls)), String) {
  case api_pure.url_to_request(clio_api_url) {
    Ok(base_api_request) -> {
      let api_request_with_query =
        api_pure.build_api_query(
          base_api_request,
          dict.to_list(filters),
          fields_to_return,
        )
      let api_response_result =
        api_impure.make_api_request(token, api_request_with_query)
      case api_response_result {
        Ok(api_resp) -> {
          let constructor = case api_resp {
            TokenNotRenewed(_) -> TokenNotRenewed(_)
            TokenRenewed(_, new_token) -> TokenRenewed(_, new_token)
          }
          case api_pure.decode_pagination(api_resp.res.body) {
            Ok(pagination) -> {
              case json_decoder(api_resp.res.body) {
                Ok(decoded_data) -> Ok(constructor(#(decoded_data, pagination)))
                Error(e) -> Error("Decode error -> " <> string.inspect(e))
              }
            }
            Error(e) ->
              Error("Unable to decode pagination -> " <> string.inspect(e))
          }
        }
        Error(message) -> Error("Error making requst to clio: " <> message)
      }
    }
    Error(e) ->
      Error("Error converting url to request -> " <> string.inspect(e))
  }
}

pub fn fetch_one_page(
  token: ClioToken,
  clio_api_url: String,
  filters: Dict(String, String),
  json_decoder: fn(String) -> Result(List(a), String),
  fields_to_return: List(String),
) -> Result(ClioYielder(a), String) {
  use base_api_request <- result.try(api_pure.url_to_request(clio_api_url))
  let api_request_with_query =
    api_pure.build_api_query(
      base_api_request,
      dict.to_list(filters),
      fields_to_return,
    )
  use api_response <- result.try(api_impure.make_api_request(
    token,
    api_request_with_query,
  ))
  use this_page_of_data <- result.try(json_decoder(api_response.res.body))
  use pagination <- result.try(api_pure.decode_pagination(api_response.res.body))
  let next_func = case pagination.next {
    Some(next_url) ->
      Some(fn() {
        fetch_one_page(token, next_url, filters, json_decoder, fields_to_return)
      })
    None -> None
  }
  let prev_func = case pagination.next {
    Some(prev_url) ->
      Some(fn() {
        fetch_one_page(token, prev_url, filters, json_decoder, fields_to_return)
      })
    None -> None
  }
  Ok(ClioYielder(this_page_of_data, prev_func, next_func))
}

pub fn fetch_all_pages(
  token: ClioToken,
  clio_api_url: String,
  filters: Dict(String, String),
  fields_to_return: List(String),
  json_decoder: Decoder(a),
) -> Result(ApiResponse(List(a)), String) {
  use base_api_request <- result.try(api_pure.url_to_request(clio_api_url))
  let api_request_with_query =
    api_pure.build_api_query(
      base_api_request,
      dict.to_list(filters),
      fields_to_return,
    )
  api_impure.fetch_all_pages_from_clio(
    token,
    api_request_with_query,
    json_decoder,
  )
}
