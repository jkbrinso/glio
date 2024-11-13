

pub type ClioValue(a) {
  ClioSome(a)
  ClioNone
  ClioValueError(message: String)
}


