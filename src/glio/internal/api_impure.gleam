import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleam/uri

import glow_auth
import glow_auth/access_token as glow_access_token

import glio/clio_users
import glio/internal/api_pure.{type ClioToken, type MyApp}

pub fn fetch_glow_token_using_temporary_code(
  my_app: MyApp,
  temporary_code: String,
) -> Result(glow_access_token.AccessToken, String) {
  let oauth_token_request =
    api_pure.build_oauth_token_request(my_app, temporary_code)
  case httpc.send(oauth_token_request) {
    Ok(resp) -> api_pure.decode_token_from_response(resp)
    Error(e) ->
      Error(
        "Failed to receive a response from Clio when attempting "
        <> "to get authorization token. More information: "
        <> string.inspect(e),
      )
  }
}

pub fn get_user_id_from_api(token_str) -> Result(String, String) {
  // Get the user's clio user id using the api  
  let assert Ok(api_uri) =
    uri.parse("https://app.clio.com/api/v4/users/who_am_i.json")
  let assert Ok(user_id_request) = request.from_uri(api_uri)
  use user_id_response: response.Response(String) <- result.try(
    make_api_request(token_str, user_id_request),
  )
  let body = user_id_response.body
  use user: clio_users.User <- result.try(case
    json.decode(body, api_pure.clio_data_decoder(clio_users.user_decoder()))
  {
    Ok(a) -> Ok(a)
    Error(e) ->
      Error(
        "Unable to decode user_id from json received from Clio"
        <> "More information: "
        <> string.inspect(e),
      )
  })
  Ok(int.to_string(user.id))
}

pub fn make_api_request(
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

pub fn fetch_all_pages_from_clio(
  clio_token: ClioToken,
  api_req_w_params: request.Request(String),
  json_decoder: fn(String) -> Result(List(a), String),
) -> Result(List(a), String) {
  make_paginated_request_tail_optimized(
    clio_token,
    api_req_w_params,
    json_decoder,
    [],
  )
}

fn make_paginated_request_tail_optimized(
  clio_token: ClioToken,
  api_req_w_params: request.Request(String),
  json_decoder: fn(String) -> Result(List(a), String),
  accumulator: List(a),
) -> Result(List(a), String) {
  use api_resp <- result.try(make_api_request(
    clio_token.access_token,
    api_req_w_params,
  ))
  use new_data <- result.try(json_decoder(api_resp.body))
  let all_data_so_far = list.flatten([accumulator, new_data])
  case api_pure.get_next_url(api_resp.body) {
    // An error state means there is no next page url, which means this is the
    // last page
    Error(_) -> Ok(all_data_so_far)
    Ok(url) -> {
      use request_for_next_page <- result.try(api_pure.url_to_request(url))
      make_paginated_request_tail_optimized(
        clio_token,
        request_for_next_page,
        json_decoder,
        all_data_so_far,
      )
    }
  }
}
