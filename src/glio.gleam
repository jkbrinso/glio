//// A library for interacting with the API of Clio, a law practice management 
//// platform

import gleam/uri.{type Uri}
import gleam/option.{type Option}

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

pub type ApiResponse(a) {
  TokenNotRenewed(res: a)
  TokenRenewed(res: a, new_token: ClioToken)
}

pub type ClioYielder(a) {
  ClioYielder(
    data: ApiResponse(List(a)),
    prev: Option(fn() -> Result(ClioYielder(a), String)),
    next: Option(fn() -> Result(ClioYielder(a), String)),
  )
}


