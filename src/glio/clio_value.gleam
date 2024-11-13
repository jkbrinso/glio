import tempo

pub type ClioValue(a) {
  ClioSome(a)
  ClioNone
  ClioValueError(message: String)
}

pub type MatterStatus {
  Pending
  Open
  Closed
}
