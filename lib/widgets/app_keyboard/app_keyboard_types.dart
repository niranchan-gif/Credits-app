/// Keyboard types indicating the primary input type for a field.
enum AppKeyboardType {
  text,
  number,
  phone,
  email,
  multiline,
}

/// The current visual layout mode of the keyboard.
enum AppKeyboardMode {
  qwerty,
  symbols,
  numeric, // Large tactile numpad (same as Quick Add)
}

/// The action triggered by the bottom-right primary action button.
enum AppKeyboardAction {
  done,
  next,
  search,
  send,
  newLine,
}
