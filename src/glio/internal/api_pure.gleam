import gleam/dict
import gleam/dynamic.{type DecodeError, type Dynamic}
import gleam/http/request.{type Request}
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri.{type Uri}

import glow_auth
import glow_auth/access_token as glow_access_token
import glow_auth/token_request
import glow_auth/uri/uri_builder

pub type MyApp {
  MyApp(id: String, secret: String, authorization_redirect_uri: Uri)
}

pub type ClioToken {
  ClioToken(
    access_token: String,
    refresh_token: String,
    expires_at: Int,
    user_id: String,
  )
}

/// Add a query parameter to a request string
pub fn add_query_parameter(
  outgoing_req: request.Request(String),
  key: String,
  value: String,
) -> request.Request(String) {
  result.unwrap(request.get_query(outgoing_req), [])
  |> list.append([#(key, value)])
  |> fn(q) { request.set_query(outgoing_req, q) }
}

pub fn get_next_url(response_body: String) -> Result(String, String) {
  use pagination <- result.try(decode_pagination(response_body))
  case pagination.next {
    None -> Error("No next page url received from Clio.")
    Some(url) -> Ok(url)
  }
}

pub fn get_previous_url(response_body: String) -> Result(String, String) {
  use pagination <- result.try(decode_pagination(response_body))
  case pagination.previous {
    None -> Error("No previous page url received from Clio.")
    Some(url) -> Ok(url)
  }
}

/// Used to decode the clio json "data" field that wraps the data in api calls
type ClioData(inner_type) {
  ClioData(data: inner_type)
}

/// Most of the data that clio returns is wrapped in a "data" field. This
/// decoder accepts a decoder function as an argument, and wraps a data field
/// decoder around it. This is to avoid having to implement a separate decoder
/// for each specific type of api call
pub fn clio_data_decoder(
  inner_decoder: fn(Dynamic) -> Result(inner_type, List(DecodeError)),
) -> fn(Dynamic) -> Result(inner_type, List(DecodeError)) {
  let outer_decoder =
    dynamic.decode1(ClioData, dynamic.field("data", inner_decoder))
  fn(d: Dynamic) {   
    case outer_decoder(d) {
      Ok(clio_data) -> Ok(clio_data.data)
      Error(e) -> Error(e)
    }
  }
}

pub fn convert_token_to_string(token: ClioToken) -> String {
  "CLIO_GLEAM_TOKEN_DATA|"
  <> token.access_token
  <> "|"
  <> token.refresh_token
  <> "|"
  <> int.to_string(token.expires_at)
  <> "|"
  <> token.user_id
}

pub fn convert_string_to_token(
  token_string: String,
) -> Result(ClioToken, String) {
  case string.split(token_string, "|") {
    [
      "CLIO_GLEAM_TOKEN_DATA",
      access_token,
      refresh_token,
      expires_at_str,
      user_id,
    ] ->
      case int.parse(expires_at_str) {
        Ok(expires_at) ->
          Ok(ClioToken(access_token, refresh_token, expires_at, user_id))
        Error(Nil) ->
          Error(
            "Unable to convert expiration time string to an "
            <> "integer. Token string passed into function: "
            <> token_string,
          )
      }
    _ ->
      Error(
        "Unable to parse string into a valid ClioToken. String that failed: "
        <> token_string,
      )
  }
}

pub fn build_oauth_token_request(my_app: MyApp, temporary_code: String) {
  let assert Ok(clio_uri) = uri.parse("https://app.clio.com")
  let client = glow_auth.Client(my_app.id, my_app.secret, clio_uri)
  let token_uri_appendage = uri_builder.RelativePath("oauth/token")
  token_request.authorization_code(
    client,
    token_uri_appendage,
    temporary_code,
    my_app.authorization_redirect_uri,
  )
}

pub fn url_to_request(url: String) -> Result(request.Request(String), String) {
  use a_uri <- result.try(case uri.parse(url) {
    Ok(valid_uri) -> Ok(valid_uri)
    Error(_) -> Error("Unable to parse url: " <> string.inspect(url))
  })
  case request.from_uri(a_uri) {
    Ok(new_uri) -> Ok(new_uri)
    Error(e) ->
      Error(
        "Unable to build request from uri.\n"
        <> "URI: "
        <> string.inspect(a_uri)
        <> "\n"
        <> "ERROR: "
        <> string.inspect(e),
      )
  }
}

type ClioMeta {
  ClioMeta(paging: ClioPaging)
}

type ClioPaging {
  ClioPaging(urls: ClioPagesUrls)
}

pub type ClioPagesUrls {
  ClioPagesUrls(previous: Option(String), next: Option(String))
}

fn meta_decoder() -> fn(Dynamic) -> Result(ClioMeta, List(DecodeError)) {
  dynamic.decode1(ClioMeta, dynamic.field("meta", paging_decoder()))
}

fn paging_decoder() -> fn(Dynamic) -> Result(ClioPaging, List(DecodeError)) {
  dynamic.decode1(ClioPaging, dynamic.field("paging", pages_urls_decoder()))
}

fn pages_urls_decoder() -> fn(Dynamic) ->
  Result(ClioPagesUrls, List(DecodeError)) {
  dynamic.decode2(
    ClioPagesUrls,
    dynamic.optional_field("previous", dynamic.string),
    dynamic.optional_field("next", dynamic.string),
  )
}

pub fn decode_pagination(json_data: String) -> Result(ClioPagesUrls, String) {
  case json.decode(json_data, meta_decoder()) {
    Ok(clio_meta) -> Ok(clio_meta.paging.urls)
    Error(e) ->
      Error(
        "Unable to decode pagination information in Clio "
        <> "response. More information: "
        <> string.inspect(e),
      )
  }
}

/// Given a Request req, returns the value of the query parameter "code"
/// included in the request.
pub fn get_code_from_req(req: Request(a)) -> Result(String, String) {
  let code_result = {
    use queries_list <- result.try(request.get_query(req))
    let queries_dict = dict.from_list(queries_list)
    dict.get(queries_dict, "code")
  }
  case code_result {
    Ok(val) -> Ok(val)
    Error(e) ->
      Error(
        "The user's request did not contain an authorization "
        <> "code. This could occur if the user was not re-directed directly "
        <> "from Clio. More information: "
        <> string.inspect(e),
      )
  }
}

pub fn build_clio_token_from_glow_token(
  glow_token: glow_access_token.AccessToken,
  user_id: String,
) -> Result(ClioToken, String) {
  case glow_token.refresh_token, glow_token.expires_at {
    Some(ref_tok), Some(expires_at) ->
      Ok(ClioToken(
        access_token: glow_token.access_token,
        refresh_token: ref_tok,
        expires_at: expires_at,
        user_id: user_id,
      ))
    refresh_option_received, expiration_option_received ->
      Error(
        "The oauth token was missing a refresh token, an expiration time, or "
        <> "both. "
        <> "\n REFRESH TOKEN: "
        <> string.inspect(refresh_option_received)
        <> "\n | EXPIRES AT: "
        <> string.inspect(expiration_option_received),
      )
  }
}

pub fn decode_token_from_response(
  resp: response.Response(String),
) -> Result(glow_access_token.AccessToken, String) {
  case glow_access_token.decode_token_from_response(resp.body) {
    Ok(token) -> Ok(token)
    Error(e) ->
      Error(
        "Unable to decode access token from the response "
        <> "received from Clio. More information: "
        <> string.inspect(e),
      )
  }
}

pub fn build_api_query(
  api_request: request.Request(String),
  filters: List(#(String, String)),
  fields_to_return: List(String),
) -> request.Request(String) {
  let fields_to_return_as_string = string.join(fields_to_return, ",")
  let api_request_with_filters =
    list.fold(filters, api_request, fn(req, param) {
      add_query_parameter(req, param.0, param.1)
    })
  let api_request_with_filters_and_fields =
    add_query_parameter(
      api_request_with_filters,
      "fields",
      fields_to_return_as_string,
    )
  api_request_with_filters_and_fields
}
