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

import glio/clio_users
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
  OriginatingAttorney
  ResponsibleAttorney
}

const all_matter_fields = [
  Id, Description, ClientId, DisplayNumber, CustomNumber, Status, Billable,
  OpenDate, CloseDate, MatterStageId, OriginatingAttorney, ResponsibleAttorney,
]

pub type MatterValue {
  MatterString(String)
  MatterInt(Int)
  MatterDate(tempo.Date)
  MatterBool(Bool)
  MatterStatus(StatusOfMatter)
  MatterOption(Option(MatterValue))
  MatterList(List(MatterValue))
  MatterUser(User)
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
    OriginatingAttorney -> "originating_attorney.{id,name}"
    ResponsibleAttorney -> "responsible_attorney.{id,name}"
  }
}

fn matter_field_to_response_key(field: MatterField) -> String {
  case field {
    Id -> "id"
    Description -> "description"
    ClientId -> "client"
    DisplayNumber -> "display_number"
    CustomNumber -> "custom_number"
    Status -> "status"
    Billable -> "billable"
    OpenDate -> "open_date"
    CloseDate -> "close_date"
    MatterStageId -> "matter_stage"
    OriginatingAttorney -> "originating_attorney"
    ResponsibleAttorney -> "responsible_attorney"
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
    Id -> field_decoder(dynamic_value, Id, int_decoder)
    Description -> field_decoder(dynamic_value, Description, string_decoder)
    ClientId -> field_decoder(dynamic_value, ClientId, client_decoder)
    DisplayNumber ->
      field_decoder(dynamic_value, DisplayNumber, option_decoder(
        _,
        string_decoder,
      ))
    CustomNumber ->
      field_decoder(dynamic_value, CustomNumber, option_decoder(
        _,
        string_decoder,
      ))
    Status ->
      field_decoder(dynamic_value, Status, option_decoder(_, status_decoder))
    Billable ->
      field_decoder(dynamic_value, Billable, option_decoder(_, bool_decoder))
    OpenDate ->
      field_decoder(dynamic_value, OpenDate, option_decoder(_, date_decoder))
    CloseDate ->
      field_decoder(dynamic_value, CloseDate, option_decoder(_, date_decoder))
    MatterStageId ->
      field_decoder(dynamic_value, MatterStageId, option_decoder(
        _,
        stage_decoder,
      ))
    OriginatingAttorney ->
      field_decoder(dynamic_value, OriginatingAttorney, option_decoder(
        _,
        user_decoder,
      ))
    ResponsibleAttorney ->
      field_decoder(dynamic_value, ResponsibleAttorney, option_decoder(
        _,
        user_decoder,
      ))
  }
}

fn field_decoder(
  dynamic_value: Dynamic,
  field: MatterField,
  inner_decoder: fn(Dynamic) -> Result(MatterValue, List(dynamic.DecodeError)),
) {
  let field_key = matter_field_to_response_key(field)
  let field_decoder = dynamic.field(field_key, inner_decoder)
  field_decoder(dynamic_value)
}

fn int_decoder(dynamic_value: Dynamic) -> Result(MatterValue, List(DecodeError)) {
  case dynamic.int(dynamic_value) {
    Ok(an_int) -> Ok(MatterInt(an_int))
    Error(e) -> Error(e)
  }
}

fn string_decoder(
  dynamic_value: Dynamic,
) -> Result(MatterValue, List(DecodeError)) {
  case dynamic.string(dynamic_value) {
    Ok(str) -> Ok(MatterString(str))
    Error(e) -> Error(e)
  }
}

fn bool_decoder(
  dynamic_value: Dynamic,
) -> Result(MatterValue, List(DecodeError)) {
  case dynamic.bool(dynamic_value) {
    Ok(a_bool) -> Ok(MatterBool(a_bool))
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

fn date_decoder(d: Dynamic) -> Result(MatterValue, List(DecodeError)) {
  todo
}

fn client_decoder(d: Dynamic) -> Result(MatterValue, List(DecodeError)) {
  todo
}

fn option_decoder(
  d: Dynamic,
  inner_decoder: fn(Dynamic) -> Result(MatterValue, List(DecodeError)),
) -> Result(MatterValue, List(DecodeError)) {
  todo
}

fn list_decoder(
  d: Dynamic,
  inner_decoder: fn(Dynamic) -> Result(MatterValue, List(DecodeError)),
) -> Result(MatterValue, List(DecodeError)) {
  todo
}

@deprecated("Delete User type in matters module")
pub type User {
  User(id: Int, name: String)
}
//@deprecated("Delete user_decoder in matters module")
//pub fn user_decoder() {
//  dynamic.decode2(
//    User,
//    dynamic.field("id", dynamic.int),
//    dynamic.field("name", dynamic.string),
//  )
//}
