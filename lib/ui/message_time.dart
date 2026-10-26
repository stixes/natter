/// Formats a message's creation time for display in a chat bubble.
///
/// The time is rendered on the device's local clock as a 24-hour `HH:MM`
/// string with zero-padded hour and minute. No seconds, AM/PM, or date.
String formatMessageTime(DateTime time) {
  final local = time.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
