import gleam/dict
import gleam/dynamic/decode
import gleam/dynamic.{type Dynamic}
import gleam/http/request.{type Request}
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri
import glio.{type ClioToken, type MyApp, ClioToken}
import glow_auth
import glow_auth/access_token as glow_access_token
import glow_auth/token_request
import glow_auth/uri/uri_builder
import gleam/function

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

pub fn get_next_url(
  response_body: String,
) -> Result(Option(String), String) {
  use pagination <- result.try(decode_pagination(response_body))
  case pagination.next {
    None -> Ok(None)
    Some(url) -> Ok(Some(url))
  }
}

pub fn get_previous_url(
  response_body: String,
) -> Result(Option(String), String) {
  use pagination <- result.try(decode_pagination(response_body))
  case pagination.previous {
    None -> Ok(None)
    Some(url) -> Ok(Some(url))
  }
}

/// Most of the data that clio returns is wrapped in a "data" field. This
/// decoder accepts a decoder function as an argument, and wraps a data field
/// decoder around it. This is to avoid having to implement a separate decoder
/// for each specific type of api call
pub fn clio_data_decoder(
  inner_decoder: decode.Decoder(a),
) -> decode.Decoder(a) {
  use val <- decode.field("data", inner_decoder)
  decode.success(val)
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

pub type ClioPagesUrls {
  ClioPagesUrls(previous: Option(String), next: Option(String))
}

fn pages_urls_decoder() -> decode.Decoder(ClioPagesUrls) {
  use previous <- decode.optional_field(
    "previous",
    None,
    decode.optional(decode.string),
  )
  use next <- decode.optional_field(
    "next",
    None,
    decode.optional(decode.string),
  )
  decode.success(ClioPagesUrls(previous, next))
}

pub fn decode_pagination(
  json_data: String,
) -> Result(ClioPagesUrls, String) {
  let paging_decoder =
    decode.optionally_at(
      ["meta", "paging"],
      ClioPagesUrls(None, None),
      pages_urls_decoder(),
    )
  json.parse(json_data, paging_decoder)
  |> result.map_error(fn(e) { string.inspect(e) })
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
        <> "both. | GLOW_TOKEN: "
        <> string.inspect(glow_token)
        <> " | USER_ID: "
        <> user_id
        <> " | REFRESH TOKEN: "
        <> string.inspect(refresh_option_received)
        <> " | EXPIRES AT: "
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
  fields_to_return: String,
) -> request.Request(String) {
  let api_request_with_filters =
    list.fold(filters, api_request, fn(req, param) {
      add_query_parameter(req, param.0, param.1)
    })
  let api_request_with_filters_and_fields =
    add_query_parameter(api_request_with_filters, "fields", fields_to_return)
  api_request_with_filters_and_fields
}
