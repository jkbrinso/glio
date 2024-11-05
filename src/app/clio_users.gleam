import gleam/dynamic

pub type User {
  User(id: Int, name: String)
}

pub fn user_decoder() {
  dynamic.decode2(
    User,
    dynamic.field("id", dynamic.int),
    dynamic.field("name", dynamic.string),
  )
}
