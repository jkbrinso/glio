//// Defines functions for general interactions with clio's api, 
//// including functions that aid in decoding and pagination across
//// all api endpoints

import gleam/dynamic.{type DecodeError, type Dynamic}
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri

import glow_auth

pub type ClioToken {
  ClioToken(
    access_token: String,
    refresh_token: String,
    expires_at: Int,
    user_id: String,
  )
}

// pub type FetchError {
//   TokenDecodeError(message: String)
// }

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

pub fn make_request(
  access_token: String,
  outgoing_req: request.Request(String),
) -> Result(response.Response(String), String) {
  let request_with_authorization_header =
    glow_auth.authorization_header(outgoing_req, access_token)
  let api_response_result =
    httpc.send(request_with_authorization_header)
    |> result.map_error(fn(e) {
      "Error when attempting to make api request. More information: "
      <> string.inspect(e)
    })
  use api_response <- result.try(api_response_result)
  case api_response.status {
    200 -> Ok(api_response)
    _ ->
      Error(
        "Clio returned an error in response to the api request. "
        <> "More information: "
        <> string.inspect(api_response),
      )
  }
}

pub fn make_paginated_request(
  clio_token: ClioToken,
  api_req_w_params: request.Request(String),
  json_decoder: fn(String) -> Result(List(a), String),
) -> Result(List(a), String) {
  make_paginated_request_helper(clio_token, api_req_w_params, json_decoder, [])
}

fn make_paginated_request_helper(
  clio_token: ClioToken,
  api_req_w_params: request.Request(String),
  json_decoder: fn(String) -> Result(List(a), String),
  accumulator: List(a),
) -> Result(List(a), String) {
  use api_resp <- result.try(make_request(
    clio_token.access_token,
    api_req_w_params,
  ))
  use new_data <- result.try(json_decoder(api_resp.body))
  let all_data_so_far = list.flatten([accumulator, new_data])
  case get_next_url(api_resp.body) {
    // An error state means there is no next page url, which means this is the
    // last page
    Error(_) -> Ok(all_data_so_far)
    Ok(url) -> {
      use request_for_next_page <- result.try(url_to_request(url))
      make_paginated_request_helper(
        clio_token,
        request_for_next_page,
        json_decoder,
        all_data_so_far,
      )
    }
  }
}

fn get_next_url(body) -> Result(String, String) {
  use pagination <- result.try(decode_pagination(body))
  case pagination.next {
    None -> Error("No next page url received from Clio.")
    Some(url) -> Ok(url)
  }
}

fn url_to_request(url: String) -> Result(request.Request(String), String) {
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

/// Used to decode the clio json "data" field that wraps the data in api calls
type ClioData(inner_type) {
  ClioData(data: inner_type)
}

/// Most of the data that clio returns is wrapped in a "data" field. This
/// decoder accepts a decoder function as an argument, and wraps a data field
/// decoder around it. This is to avoid having to implement a separate decoder
/// for each specific type of api call
pub fn clio_data_decoder(
  inner_decoder: fn(Dynamic) -> Result(inner_type, List(dynamic.DecodeError)),
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
        "Unable to parse string into a ClioToken. String that failed: "
        <> token_string,
      )
  }
}
