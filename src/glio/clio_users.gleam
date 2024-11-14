import gleam/dict.{type Dict}
import gleam/dynamic.{type DecodeError, type Dynamic}
import gleam/list
import gleam/option.{type Option}

pub type UserField {
  Id
  Name
}

pub type UserValue {
  UserString(String)
  UserInt(Int)
  UserOption(Option(UserValue))
}

pub fn user_decoder(
  dynamic_value: Dynamic,
  fields: List(UserField),
) -> Result(Dict(UserField, UserValue), List(DecodeError)) {
  case fields {
    [] -> Ok(dict.new())
    [head_field, ..tail] -> {
      let decoded_head = decode_by_field(dynamic_value, head_field)
      let decoded_tail = user_decoder(dynamic_value, tail)
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
  field: UserField,
) -> Result(UserValue, List(dynamic.DecodeError)) {
  case field {
    Id -> int_decoder(dynamic_value)
    Name -> string_decoder(dynamic_value)
  }
}

fn int_decoder(dynamic_value: Dynamic) -> Result(UserValue, List(DecodeError)) {
  case dynamic.int(dynamic_value) {
    Ok(an_int) -> Ok(UserInt(an_int))
    Error(e) -> Error(e)
  }
}

fn string_decoder(
  dynamic_value: Dynamic,
) -> Result(UserValue, List(DecodeError)) {
  case dynamic.string(dynamic_value) {
    Ok(str) -> Ok(UserString(str))
    Error(e) -> Error(e)
  }
}
