import gleam/dynamic
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleam/uri
import glio/internal/api_pure.{
  type ApiResponse, type ClioToken, type MyApp, Failure, Success,
  SuccessWithNewToken,
}
import glow_auth
import glow_auth/access_token as glow_access_token

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

type User {
  User(id: Int, name: String)
}

fn user_decoder() {
  dynamic.decode2(
    User,
    dynamic.field("id", dynamic.int),
    dynamic.field("name", dynamic.string),
  )
}

pub fn get_user_id_from_api(token_str) -> ApiResponse(String) {
  // Get the user's clio user id using the api  
  let assert Ok(api_uri) =
    uri.parse("https://app.clio.com/api/v4/users/who_am_i.json")
  let assert Ok(user_id_request) = request.from_uri(api_uri)
  case make_api_request(token_str, user_id_request) {
    Success(user_id_response) -> {
      let body = user_id_response.body
      case json.decode(body, api_pure.clio_data_decoder(user_decoder())) {
        Ok(user) -> Success(int.to_string(user.id))
        Error(e) ->
          Failure(
            "Unable to decode user_id from json received from Clio"
            <> "More information: "
            <> string.inspect(e),
          )
      }
    }
    SuccessWithNewToken(res, new_token) -> todo
    Failure(message) -> todo
  }
}

pub fn make_api_request(
  token: ClioToken,
  outgoing_req: request.Request(String),
) -> ApiResponse(response.Response(String)) {
  case glow_access_token.time_now() - token.expires_at {
    t if t < 60 -> {
      use token <- refresh_token_then(token)
      case make_api_request(token, outgoing_req) {
        Success(res) -> SuccessWithNewToken(res, token)
        other -> other
      }
    }
    _ -> {
      let request_with_authorization_header =
        glow_auth.authorization_header(outgoing_req, token.access_token)
      let api_response_result =
        httpc.send(request_with_authorization_header)
        |> result.map_error(fn(e) {
          "Error when attempting to make api request. More information: "
          <> string.inspect(e)
        })
      case api_response_result {
        Ok(api_response) -> {
          case api_response.status {
            200 -> Success(api_response)
            _ ->
              Failure(
                "Clio returned an error in response to the api request. "
                <> "More information: "
                <> string.inspect(api_response),
              )
          }
        }
        Error(e) -> Failure(string.inspect(e))
      }
    }
  }
}

fn refresh_token_then(token, next) -> ApiResponse(response.Response(String)) {
  todo
}

pub fn fetch_all_pages_from_clio(
  clio_token: ClioToken,
  api_req_w_params: request.Request(String),
  json_decoder: fn(String) -> Result(List(a), String),
) -> ApiResponse(List(a)) {
  make_recursive_paginated_request(
    clio_token,
    api_req_w_params,
    json_decoder,
    [],
  )
}

fn make_recursive_paginated_request(
  clio_token: ClioToken,
  api_req_w_params: request.Request(String),
  json_decoder: fn(String) -> Result(List(a), String),
  accumulator: List(a),
) -> ApiResponse(List(a)) {
  case make_api_request(clio_token, api_req_w_params) {
    Success(api_resp) -> fred(api_resp, json_decoder, accumulator, clio_token)

    SuccessWithNewToken(api_resp, new_token) ->
      case fred(api_resp, json_decoder, accumulator, new_token) {
        Success(data) -> SuccessWithNewToken(data, new_token)
        Failure(message) -> Failure(message)
        _ ->
          Failure(
            "fred thinks we need a new token, but we already gave him one",
          )
      }

    Failure(message) -> Failure(message)
  }
}

fn fred(
  api_resp: response.Response(String),
  json_decoder: fn(String) -> Result(List(a), String),
  accumulator: List(a),
  clio_token: ClioToken,
) -> ApiResponse(List(a)) {
  case json_decoder(api_resp.body) {
    Error(e) -> Failure(string.inspect(e))
    Ok(new_data) -> {
      let all_data_so_far = list.flatten([accumulator, new_data])
      case api_pure.get_next_url(api_resp.body) {
        // An error state means there is no next page url, which means this is the
        // last page
        Error(_) -> Success(all_data_so_far)
        Ok(url) -> {
          case api_pure.url_to_request(url) {
            Ok(request_for_next_page) ->
              make_recursive_paginated_request(
                clio_token,
                request_for_next_page,
                json_decoder,
                all_data_so_far,
              )
            Error(e) -> Failure(string.inspect(e))
          }
        }
      }
    }
  }
}
