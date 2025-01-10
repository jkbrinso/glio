import gleam/dynamic
import gleam/dynamic/decode.{type Decoder}
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/uri
import glio/internal/api_pure.{
  type ApiResponse, type ClioToken, type MyApp, TokenNotRenewed, TokenRenewed,
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

pub fn get_user_id_from_api(token_str) -> Result(ApiResponse(String), String) {
  // Get the user's clio user id using the api  
  let assert Ok(api_uri) =
    uri.parse("https://app.clio.com/api/v4/users/who_am_i.json")
  let assert Ok(user_id_request) = request.from_uri(api_uri)
  let decode_body = json.decode(_, api_pure.clio_data_decoder(user_decoder()))
  case make_api_request(token_str, user_id_request) {
    Ok(TokenNotRenewed(user_id_response)) -> {
      case decode_body(user_id_response.body) {
        Ok(user) -> Ok(TokenNotRenewed(int.to_string(user.id)))
        Error(e) ->
          Error(
            "api_impure.get_user_id_from_api() unable to decode user_id "
            <> "from json received from Clio. | JSON: "
            <> user_id_response.body
            <> " | ERROR: "
            <> string.inspect(e),
          )
      }
    }
    Ok(TokenRenewed(user_id_response, new_token)) -> {
      case decode_body(user_id_response.body) {
        Ok(user) -> Ok(TokenRenewed(int.to_string(user.id), new_token))
        Error(e) ->
          Error(
            "api_impure.get_user_id_from_api() unable to decode "
            <> "user_id from json received from Clio. | JSON: "
            <> user_id_response.body
            <> " | ERROR: "
            <> string.inspect(e),
          )
      }
    }
    Error(e) -> Error("api_impure.get_user_id_from_api() error making 
      request to clio: " <> string.inspect(e))
  }
}

pub fn make_api_request(
  my_app: MyApp,
  token: ClioToken,
  outgoing_req: request.Request(String),
) -> Result(ApiResponse(response.Response(String)), String) {
  case glow_access_token.time_now() - token.expires_at {
    // token is about to expire or has expired, renew it
    t if t < 60 -> {
      use new_token <- refresh_token_then(token, my_app)
      case make_api_request(new_token, outgoing_req) {
        Ok(TokenNotRenewed(res)) -> Ok(TokenRenewed(res, new_token))

        Ok(TokenRenewed(_, _)) ->
          Error(
            "api.impure.make_api_request() - An api 
          request was made that required a renewed token. The token was renewed
          but execution proceeded down the wrong branch as if it needed to be
          renewed a second time.",
          )

        Error(e) ->
          Error("api.impure.make_api_request() -> " <> string.inspect(e))
      }
    }

    // token is not expired
    _ -> {
      let request_with_authorization_header =
        glow_auth.authorization_header(outgoing_req, token.access_token)
      let api_response_result =
        httpc.send(request_with_authorization_header)
        |> result.map_error(fn(e) {
          "api.impure.make_api_request() Error in sending request to clio -> "
          <> string.inspect(e)
        })
      case api_response_result {
        Ok(api_response) -> {
          case api_response.status {
            200 -> Ok(TokenNotRenewed(api_response))
            _ ->
              Error(
                "Clio returned an error in response to the api request: "
                <> string.inspect(api_response),
              )
          }
        }
        Error(e) -> Error(string.inspect(e))
      }
    }
  }
}

fn refresh_token_then(
  token: ClioToken,
  my_app: MyApp,
  next: fn(ClioToken) -> Result(a, String),
) -> Result(a, String) {
  let assert Ok(clio_uri) = uri.parse("https://app.clio.com/oauth/token")
  let client = glow_auth.Client(my_app.id, my_app.secret, clio_uri)
  let full_uri = glow_auth.
  let req = token_request.refresh(client, clio_uri, token.refresh_token)
  let res = case httpc.send(req) {
    Ok(resp) -> api_pure.decode_token_from_response(resp)
    Error(e) ->
      Error(
        "Failed to receive a response from Clio when attempting "
        <> "to get authorization token. More information: "
        <> string.inspect(e),
      )
  }
  case res {
    Ok(glow_token) -> {
      use new_clio_token <- result.try(
        api_pure.build_clio_token_from_glow_token(glow_token, token.user_id),
      )
      next(token)
    }
    Error(e) -> Error(e)
  }
}

pub fn fetch_all_pages_from_clio(
  clio_token: ClioToken,
  api_req_w_params: request.Request(String),
  one_item_decoder: Decoder(a),
) -> Result(ApiResponse(List(a)), String) {
  make_recursive_paginated_request(
    clio_token,
    api_req_w_params,
    one_item_decoder,
    TokenNotRenewed([]),
  )
}

fn make_recursive_paginated_request(
  clio_token: ClioToken,
  api_req_w_params: request.Request(String),
  json_decoder: Decoder(a),
  accumulator: ApiResponse(List(a)),
) -> Result(ApiResponse(List(a)), String) {
  case make_api_request(clio_token, api_req_w_params) {
    Ok(TokenNotRenewed(api_resp)) ->
      parse_response(api_resp, json_decoder, accumulator, clio_token)

    Ok(TokenRenewed(api_resp, new_token)) ->
      parse_response(
        api_resp,
        json_decoder,
        TokenRenewed(accumulator.res, new_token),
        new_token,
      )

    Error(message) -> Error(message)
  }
}

fn parse_response(
  api_resp: response.Response(String),
  one_item_decoder: Decoder(a),
  accumulator: ApiResponse(List(a)),
  clio_token: ClioToken,
) -> Result(ApiResponse(List(a)), String) {
  case run_decoder(dynamic.from(api_resp.body), one_item_decoder) {
    Error(e) ->
      Error(
        "api_impure.parse_response(): Errors parsing response. "
        <> " | ERRORS: "
        <> string.inspect(e)
        <> " | RESPONSE: "
        <> string.inspect(api_resp.body),
      )

    Ok(new_data) -> {
      let all_data_so_far = accumulate_api_response(accumulator, new_data)
      case api_pure.get_next_url(api_resp.body) {
        Ok(None) -> Ok(all_data_so_far)
        Ok(Some(url)) ->
          case api_pure.url_to_request(url) {
            Ok(request_for_next_page) ->
              make_recursive_paginated_request(
                clio_token,
                request_for_next_page,
                one_item_decoder,
                all_data_so_far,
              )
            Error(e) -> Error(string.inspect(e))
          }
        Error(e) -> Error(string.inspect(e))
      }
    }
  }
}

fn run_decoder(
  dyn: dynamic.Dynamic,
  one_item_decoder: Decoder(a),
) -> Result(List(a), List(decode.DecodeError)) {
  let decoder =
    decode.field("data", decode.list(one_item_decoder), decode.success(_))
  decode.run(dyn, decoder)
}

fn accumulate_api_response(
  acc: ApiResponse(List(a)),
  new: List(a),
) -> ApiResponse(List(a)) {
  let new_list = list.flatten([acc.res, new])
  case acc {
    TokenNotRenewed(_) -> TokenNotRenewed(new_list)
    TokenRenewed(_, new_token) -> TokenRenewed(new_list, new_token)
  }
}
