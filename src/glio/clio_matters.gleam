import gleam/dict.{type Dict}
import gleam/dynamic
import gleam/http/request
import gleam/json
import gleam/result
import gleam/string
import gleam/uri
import gleam/option.{type Option}

import glio/internal/api_impure
import glio/internal/api_pure


pub type MatterData {
  Id(Int)
  Description(String)
  DisplayNumber(Option(String))
}

pub type Matter {
  Matter(
    id: Int,
    description: String,
    display_number: String,
  )
}

pub fn matter_decoder() {
  dynamic.decode3(
    Matter,
    dynamic.field("id", dynamic.int),
    dynamic.field("display_number", dynamic.string),
    dynamic.field("description", dynamic.string),
  )
}

pub fn fetch_matters_all_pages(
  token_data: String,
  query_parameters: Dict(String, String),
  fields: List(String),
) {
  use token <- result.try(api_pure.convert_string_to_token(token_data))
  let assert Ok(api_uri) = uri.parse("https://app.clio.com/api/v4/matters.json")
  let assert Ok(api_req) = request.from_uri(api_uri)
  todo
}

pub fn fetch_users_matters(token_data: String) -> Result(List(Matter), String) {
  use token <- result.try(api_pure.convert_string_to_token(token_data))
  let assert Ok(api_uri) = uri.parse("https://app.clio.com/api/v4/matters.json")
  let assert Ok(api_req) = request.from_uri(api_uri)
  let api_request_with_parameters =
    api_req
    |> api_pure.add_query_parameter("responsible_attorney_id", token.user_id)
    |> api_pure.add_query_parameter("status", "open,pending")
    |> api_pure.add_query_parameter("fields", "id,display_number,description")
  api_impure.make_paginated_request(
    token,
    api_request_with_parameters,
    decode_matter_json,
  )
}

fn decode_matter_json(json_data: String) -> Result(List(Matter), String) {
  case
    json.decode(
      json_data,
      api_pure.clio_data_decoder(dynamic.list(matter_decoder())),
    )
  {
    Ok(matter_data) -> Ok(matter_data)
    Error(e) ->
      Error(
        "Unable to decode the json received from Clio for a matter. "
        <> "More information: "
        <> string.inspect(e),
      )
  }
}
