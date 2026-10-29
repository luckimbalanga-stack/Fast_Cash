const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

const statusLabels = {
  'pending': 'En attente',
  'pin_required': 'Code PIN requis',
  'accepted': 'Acceptée',
  'refused': 'Refusée',
  'payment_pending': 'Paiement en attente',
  'payment_confirmed': 'Paiement confirmé',
  'cash_delivered': 'Scan effectué',
  'completed': 'Terminée',
  'cancelled': 'Annulée',
};

String formatPhone(String phone) {
  final digits = phone.replaceAll('+243', '');
  if (digits.length != 9) return phone;
  return '+243 ${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6)}';
}

String groupDigits(num value) {
  final negative = value < 0;
  final raw = value.abs().round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(raw[i]);
  }
  return negative ? '-$buffer' : buffer.toString();
}

String formatMoney(num amount, String currency) {
  if (currency == 'CDF') return '${groupDigits(amount)} CDF';
  final whole = amount % 1 == 0;
  final text = whole ? groupDigits(amount) : amount.toStringAsFixed(2).replaceAll('.', ',');
  return '$text USD';
}

String formatDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final date = DateTime.parse(iso).toLocal();
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${date.day} ${months[date.month - 1]} ${date.year} · $hour:$minute';
}

String formatDistance(num meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
}

String statusLabel(String status, {String? type}) {
  if (type == 'deposit' && status == 'cash_delivered') return 'Espèces reçues';
  if (type == 'deposit' && status == 'payment_confirmed') return 'Dépôt confirmé';
  return statusLabels[status] ?? status;
}
