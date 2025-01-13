import gleam/dict
import gleam/http/cookie
import gleam/http/request
import gleam/http/response
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import glio.{type ClioToken}
import glio/internal/api_pure

pub fn retrieve_token(req: request.Request(a)) -> Result(ClioToken, String) {
  use token_str <- result.try(
    request.get_cookies(req)
    |> dict.from_list()
    |> dict.get("api_token")
    |> result.replace_error(
      "There was no token in the request. Cookies "
      <> "present in request: "
      <> string.inspect(request.get_cookies(req)),
    ),
  )
  api_pure.convert_string_to_token(token_str)
}

pub fn set_token_cookie(
  resp: response.Response(a),
  token: ClioToken,
) -> response.Response(a) {
  let cookie_attributes =
    cookie.Attributes(
      max_age: Some(2_592_000),
      domain: None,
      path: None,
      secure: True,
      http_only: True,
      same_site: Some(cookie.Strict),
    )
  response.set_cookie(
    resp,
    "api_token",
    api_pure.convert_token_to_string(token),
    cookie_attributes,
  )
}
