/// Contacts returned by `GET /api/v1/users/support/emergency` and
/// `GET /api/v1/users/support/customer-service`.
///
/// The two endpoints use different shapes (the spec's examples):
///
/// * emergency → `{ id, name, number, isActive, … }`
/// * customer-service → `{ id, name, location, mobileNumber, whatsappNumber, isActive, … }`
///
/// and both wrap their rows in `data: [ … ]`, so [parseSupportContacts] must
/// handle a list, a lone object, or an unwrapped payload.
class SupportContact {
  const SupportContact({
    required this.name,
    this.phone,
    this.whatsappNumber,
    this.location,
  });

  final String name;

  /// `number` (emergency) or `mobileNumber` / `phone` (customer service).
  final String? phone;
  final String? whatsappNumber;
  final String? location;

  bool get hasName => name.trim().isNotEmpty;

  factory SupportContact.fromJson(Map<String, dynamic> json) {
    String? textOf(List<String> keys) {
      for (final key in keys) {
        final raw = json[key];
        if (raw == null) continue;
        final value = raw.toString().trim();
        if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
      }
      return null;
    }

    return SupportContact(
      name: textOf(const ['name', 'title', 'label']) ?? '',
      phone: textOf(const [
        'number',
        'mobileNumber',
        'mobile',
        'phoneNumber',
        'phone',
      ]),
      whatsappNumber: textOf(const ['whatsappNumber', 'whatsapp']),
      location: textOf(const ['location', 'address']),
    );
  }

  bool get isEmpty => !hasName && phone == null && whatsappNumber == null;
}

/// Extracts the usable rows from either support endpoint's response.
/// Inactive rows (`isActive == false`) and rows with nothing to show are
/// dropped; an unexpected payload yields an empty list instead of throwing.
List<SupportContact> parseSupportContacts(dynamic response) {
  dynamic data = response;
  if (data is Map) {
    data = data['data'] ?? data['contacts'] ?? data['list'] ?? data;
  }
  final dynamic rows = data is List
      ? data
      : data is Map
          ? <dynamic>[data]
          : const <dynamic>[];

  final contacts = <SupportContact>[];
  for (final row in rows) {
    if (row is! Map) continue;
    if (row['isActive'] == false) continue;
    try {
      final contact = SupportContact.fromJson(Map<String, dynamic>.from(row));
      if (!contact.isEmpty) contacts.add(contact);
    } catch (_) {
      // Skip malformed rows rather than failing the whole modal.
    }
  }
  return contacts;
}
