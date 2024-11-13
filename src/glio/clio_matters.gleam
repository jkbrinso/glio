import gleam/dict.{type Dict}
import gleam/dynamic.{type DecodeError, type Dynamic}
import gleam/http/request
import gleam/json
import gleam/option.{type Option}
import gleam/result
import gleam/string
import gleam/uri

// This package is gtempo
import tempo.{type Date}
import tempo/date

import glio/clio_value.{type ClioValue}
import glio/internal/api_impure
import glio/internal/api_pure

const matter_api_url = "https://app.clio.com/api/v4/matters.json"

pub type Matter {
  Matter(
    id: ClioValue(String),
    description: ClioValue(String),
    client_id: ClioValue(String),
    display_number: ClioValue(String),
    custom_number: ClioValue(String),
    status: ClioValue(MatterStatus),
    billable: ClioValue(Bool),
    open_date: ClioValue(tempo.Date),
    close_date: ClioValue(tempo.Date),
    matter_stage_id: ClioValue(String),
    originating_attorney_id: ClioValue(String),
    responsible_attorney_id: ClioValue(String),
  )
}

const all_matter_fields = [
  "id", "description", "client_id", "display_number", "custom_number", "status",
  "billable", "open_date", "close_date", "matter_stage{id, name}",
  "originating_attorney{id, name}", "responsible_attorney{id, name}",
]

pub type MatterField {
  Id
  Description
  ClientId
  DisplayNumber
  CustomNumber
  Status
  Billable
  OpenDate
  CloseDate
  MatterStageId
  OriginatingAttorneyId
  ResponsibleAttorneyId
}

pub type MatterStatus {
  Pending
  Open
  Closed
}

fn matter_field_to_query_string(field: MatterField) -> String {
  case field {
    Id -> "id"
    Description -> "description"
    ClientId -> "client{id,name}"
    DisplayNumber -> "display_number"
    CustomNumber -> "custom_number"
    Status -> "status"
    Billable -> "billable"
    OpenDate -> "open_date"
    CloseDate -> "close_date"
    MatterStageId -> "matter_stage{id,name}"
    OriginatingAttorneyId -> "originating_attorney.{id,name}"
    ResponsibleAttorneyId -> "responsible_attorney.{id,name}"
  }
}

pub fn fetch_this_users_open_matters(
  token_data: String,
) -> Result(List(Matter), String) {
  use token <- result.try(api_pure.convert_string_to_token(token_data))
  use api_request <- result.try(
    request.to(matter_api_url)
    |> result.map_error(fn(_: Nil) {
      "Unknown error formulating a proper request " <> "to: " <> matter_api_url
    }),
  )
  let filters =
    dict.from_list([
      #("responsible_attorney_id", token.user_id),
      #("status", "open,pending"),
    ])
  let fields_to_return = all_matter_fields
  let api_request_with_queries =
    api_pure.build_api_query(api_request, filters, fields_to_return)
  api_impure.fetch_all_pages_from_clio(
    token,
    api_request_with_queries,
    decode_matter_json(_, all_matter_fields),
  )
}

fn decode_matter_json(
  json_data: String,
  fields: List(String),
) -> Result(List(Matter), String) {
  case
    json.decode(
      json_data,
      api_pure.clio_data_decoder(dynamic.list(matter_decoder())),
    )
  {
    Ok(matter_data) -> Ok(matter_data)
    Error(e) ->
      Error(
        "Unable to decode the json received from Clio for a matter. \n"
        <> "JSON DATA RECEIVED: "
        <> string.inspect(json_data)
        <> " \n"
        <> "DECODER ERROR MESSAGE: "
        <> string.inspect(e)
        <> " \n",
      )
  }
}

fn matter_decoder() -> fn(Dynamic) -> Result(Matter, List(DecodeError)) {
  todo
}

fn clio_value_decoder(
  inner_decoder: fn(Dynamic) -> Result(a, List(DecodeError)),
) -> fn(Dynamic) -> Result(ClioValue(a), List(DecodeError)) {
  todo
}

fn user_decoder(d: Dynamic) -> Result(ClioValue(String), List(DecodeError)) {
  todo
}

fn status_decoder(
  d: Dynamic,
) -> Result(ClioValue(MatterStatus), List(DecodeError)) {
  todo
}

fn stage_decoder(d: Dynamic) -> Result(ClioValue(String), List(DecodeError)) {
  todo
}
