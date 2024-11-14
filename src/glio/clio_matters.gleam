import gleam/dict.{type Dict}
import gleam/dynamic.{type DecodeError, type Dynamic}
import gleam/http/request
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri

// This package is gtempo
import tempo.{type Date}
import tempo/date

import glio/internal/api_impure
import glio/internal/api_pure

const matter_api_url = "https://app.clio.com/api/v4/matters.json"

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

const all_matter_fields = [
  Id, Description, ClientId, DisplayNumber, CustomNumber, Status, Billable,
  OpenDate, CloseDate, MatterStageId, OriginatingAttorneyId,
  ResponsibleAttorneyId,
]

pub type MatterValue {
  MatterString(String)
  MatterInt(Int)
  MatterDate(tempo.Date)
  MatterStatus(StatusOfMatter)
  MatterOption(Option(MatterValue))
  MatterList(List(MatterValue))
}

pub type StatusOfMatter {
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
) -> Result(List(Dict(MatterField, MatterValue)), String) {
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
    api_pure.build_api_query(
      api_request,
      filters,
      list.map(fields_to_return, matter_field_to_query_string),
    )
  api_impure.fetch_all_pages_from_clio(
    token,
    api_request_with_queries,
    decode_matter_json(_, all_matter_fields),
  )
}

fn decode_matter_json(
  json_data: String,
  fields: List(MatterField),
) -> Result(List(Dict(MatterField, MatterValue)), String) {
  result.map_error(
    json.decode(
      json_data,
      api_pure.clio_data_decoder(dynamic.list(matter_decoder(_, fields))),
    ),
    fn(e) {
      "Unable to decode the json received from Clio for a matter. \n"
      <> "JSON DATA RECEIVED: "
      <> string.inspect(json_data)
      <> " \n"
      <> "DECODER ERRORS: "
      <> string.inspect(e)
      <> " \n"
    },
  )
}

fn matter_decoder(
  dynamic_value: Dynamic,
  fields: List(MatterField),
) -> Result(Dict(MatterField, MatterValue), List(DecodeError)) {
  case fields {
    [] -> Ok(dict.new())
    [head_field, ..tail] -> {
      let decoded_head = decode_by_field(dynamic_value, head_field)
      let decoded_tail = matter_decoder(dynamic_value, tail)
      case decoded_head, decoded_tail {
        Ok(head_value), Ok(tail_dict) ->
          Ok(dict.insert(tail_dict, head_field, head_value))
        Error(head_errors), Error(tail_errors) ->
          Error(list.flatten([head_errors, tail_errors]))
        Ok(_), Error(tail_errors) -> Error(tail_errors)
        Error(head_errors), Ok(_) -> Error(head_errors)
      }
    }
  }
}

fn decode_by_field(
  dynamic_value: Dynamic,
  field: MatterField,
) -> Result(MatterValue, List(dynamic.DecodeError)) {
  case field {
    Id -> int_decoder(dynamic_value)
    Description -> string_decoder(dynamic_value)
    _ -> todo
  }
}

pub fn int_decoder(
  dynamic_value: Dynamic,
) -> Result(MatterValue, List(DecodeError)) {
  case dynamic.int(dynamic_value) {
    Ok(an_int) -> Ok(MatterInt(an_int))
    Error(e) -> Error(e)
  }
}

pub fn string_decoder(
  dynamic_value: Dynamic,
) -> Result(MatterValue, List(DecodeError)) {
  case dynamic.string(dynamic_value) {
    Ok(str) -> Ok(MatterString(str))
    Error(e) -> Error(e)
  }
}

fn user_decoder(d: Dynamic) -> Result(MatterValue, List(DecodeError)) {
  todo
}

fn status_decoder(d: Dynamic) -> Result(MatterValue, List(DecodeError)) {
  todo
}

fn stage_decoder(d: Dynamic) -> Result(MatterValue, List(DecodeError)) {
  todo
}
