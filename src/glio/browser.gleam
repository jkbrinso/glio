import glio/internal/api_pure.{type ClioToken}

import wisp

import gleam/dict
import gleam/http/cookie
import gleam/http/request
import gleam/http/response
import gleam/option.{None, Some}
import gleam/result
import gleam/string

pub fn retrieve_token(req: wisp.Request) -> Result(ClioToken, String) {
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

pub fn set_token_cookie(resp: wisp.Response, token: ClioToken) -> wisp.Response {
  let cookie_attributes =
    cookie.Attributes(
      max_age: Some(2_592_000),
      domain: None,
      path: None,
      secure: True,
      http_only: True,
      same_site: Some(cookie.Strict),
    )
  response.set_cookie(resp, "api_token", token.access_token, cookie_attributes)
}
