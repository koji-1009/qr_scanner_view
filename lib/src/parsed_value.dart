// Typed interpretation of decoded barcode strings. Parsing happens in Dart,
// on the same `Barcode.value` both platforms deliver, so the result is
// identical on iOS and Android by construction.
import 'dart:convert' show utf8;

import 'package:flutter/foundation.dart';

import 'models.dart';

/// Structured interpretation of a [Barcode.value].
///
/// Obtain one through [BarcodeParsing.parsed] or [ParsedValue.parse]; switch
/// over the sealed subtypes to handle each kind:
///
/// ```dart
/// switch (barcode.parsed) {
///   case WifiValue(:final ssid, :final password): ...
///   case UrlValue(:final url): ...
///   case TextValue(:final text): ...
///   ...
/// }
/// ```
///
/// A payload that announces a type but fails to parse (e.g. `WIFI:` without
/// an SSID) falls back to [TextValue].
@immutable
sealed class ParsedValue {
  const ParsedValue();

  /// Parses [value] as decoded from a barcode of [format].
  ///
  /// [format] drives the retail types: an EAN-13 starting with 978/979 is an
  /// [IsbnValue], other EAN/UPC values are [ProductValue]s. Everything else
  /// is recognized by its payload prefix, case-insensitively.
  static ParsedValue parse(String value, {BarcodeFormat format = .unknown}) {
    if (value.isNotEmpty) {
      final retail = switch (format) {
        .ean13 =>
          value.startsWith('978') || value.startsWith('979')
              ? IsbnValue(value)
              : ProductValue(value),
        .ean8 || .upcA || .upcE => ProductValue(value),
        _ => null,
      };
      if (retail != null) return retail;
    }
    final upper = value.toUpperCase();
    final parsed = switch (value) {
      _ when upper.startsWith('WIFI:') => _parseWifi(value),
      _ when upper.startsWith('MECARD:') => _parseMeCard(value),
      _ when upper.startsWith('BEGIN:VCARD') => _parseVCard(value),
      _
          when upper.startsWith('BEGIN:VEVENT') ||
              upper.startsWith('BEGIN:VCALENDAR') =>
        _parseCalendar(value),
      _ when upper.startsWith('MATMSG:') => _parseMatmsg(value),
      _ when upper.startsWith('MAILTO:') => _parseMailto(value),
      _ when upper.startsWith('SMSTO:') || upper.startsWith('MMSTO:') =>
        _parseSmsTo(value),
      _ when upper.startsWith('SMS:') || upper.startsWith('MMS:') =>
        _parseSmsUri(value),
      _ when upper.startsWith('TEL:') => _parseTel(value),
      _ when upper.startsWith('GEO:') => _parseGeo(value),
      _ when upper.startsWith('URLTO:') => _parseUrlTo(value),
      _ when upper.startsWith('HTTP://') || upper.startsWith('HTTPS://') =>
        UrlValue(url: value),
      _ when _bareEmail.hasMatch(value) => EmailValue(address: value),
      _ => null,
    };
    return parsed ?? TextValue(value);
  }
}

/// Free-form text: the fallback when no structured type matches.
final class TextValue extends ParsedValue {
  const TextValue(this.text);

  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TextValue && other.text == text;

  @override
  int get hashCode => Object.hash(TextValue, text);

  @override
  String toString() => 'TextValue("$text")';
}

/// A web address (`http://`, `https://` or a `URLTO:` bookmark).
final class UrlValue extends ParsedValue {
  const UrlValue({required this.url, this.title});

  final String url;

  /// Bookmark title; only `URLTO:` payloads carry one.
  final String? title;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UrlValue && other.url == url && other.title == title;

  @override
  int get hashCode => Object.hash(UrlValue, url, title);

  @override
  String toString() => 'UrlValue($url)';
}

/// Security scheme of a [WifiValue].
enum WifiSecurity { open, wep, wpa }

/// Wi-Fi join configuration (`WIFI:` payload).
final class WifiValue extends ParsedValue {
  const WifiValue({
    required this.ssid,
    this.password,
    this.security = .open,
    this.hidden = false,
  });

  final String ssid;
  final String? password;
  final WifiSecurity security;
  final bool hidden;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WifiValue &&
          other.ssid == ssid &&
          other.password == password &&
          other.security == security &&
          other.hidden == hidden;

  @override
  int get hashCode => Object.hash(WifiValue, ssid, password, security, hidden);

  @override
  String toString() =>
      'WifiValue($ssid, ${security.name}${hidden ? ', hidden' : ''})';
}

/// An email composition (`mailto:`, `MATMSG:` or a bare address).
final class EmailValue extends ParsedValue {
  const EmailValue({required this.address, this.subject, this.body});

  final String address;
  final String? subject;
  final String? body;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmailValue &&
          other.address == address &&
          other.subject == subject &&
          other.body == body;

  @override
  int get hashCode => Object.hash(EmailValue, address, subject, body);

  @override
  String toString() => 'EmailValue($address)';
}

/// A phone number (`tel:` payload).
final class PhoneValue extends ParsedValue {
  const PhoneValue(this.number);

  final String number;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PhoneValue && other.number == number;

  @override
  int get hashCode => Object.hash(PhoneValue, number);

  @override
  String toString() => 'PhoneValue($number)';
}

/// An SMS/MMS composition (`SMSTO:` / `sms:` payloads).
final class SmsValue extends ParsedValue {
  const SmsValue({required this.number, this.message});

  final String number;
  final String? message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmsValue && other.number == number && other.message == message;

  @override
  int get hashCode => Object.hash(SmsValue, number, message);

  @override
  String toString() => 'SmsValue($number)';
}

/// A geographic position (`geo:` payload).
final class GeoValue extends ParsedValue {
  const GeoValue({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.query,
  });

  final double latitude;
  final double longitude;
  final double? altitude;

  /// Free-text query (`?q=`), e.g. a place name.
  final String? query;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoValue &&
          other.latitude == latitude &&
          other.longitude == longitude &&
          other.altitude == altitude &&
          other.query == query;

  @override
  int get hashCode =>
      Object.hash(GeoValue, latitude, longitude, altitude, query);

  @override
  String toString() => 'GeoValue($latitude, $longitude)';
}

/// Contact details (`MECARD:` or vCard payload).
final class ContactValue extends ParsedValue {
  const ContactValue({
    this.name,
    this.organization,
    this.title,
    this.phones = const [],
    this.emails = const [],
    this.urls = const [],
    this.addresses = const [],
    this.note,
  });

  final String? name;
  final String? organization;
  final String? title;
  final List<String> phones;
  final List<String> emails;
  final List<String> urls;
  final List<String> addresses;
  final String? note;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContactValue &&
          other.name == name &&
          other.organization == organization &&
          other.title == title &&
          listEquals(other.phones, phones) &&
          listEquals(other.emails, emails) &&
          listEquals(other.urls, urls) &&
          listEquals(other.addresses, addresses) &&
          other.note == note;

  @override
  int get hashCode => Object.hash(
    ContactValue,
    name,
    organization,
    title,
    Object.hashAll(phones),
    Object.hashAll(emails),
    Object.hashAll(urls),
    Object.hashAll(addresses),
    note,
  );

  @override
  String toString() =>
      'ContactValue(${name ?? (phones.isEmpty ? '' : phones.first)})';
}

/// A calendar event (iCalendar `VEVENT` payload). Fields the payload omits
/// or that fail to parse are null.
final class CalendarEventValue extends ParsedValue {
  const CalendarEventValue({
    this.summary,
    this.location,
    this.description,
    this.start,
    this.end,
  });

  final String? summary;
  final String? location;
  final String? description;
  final DateTime? start;
  final DateTime? end;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalendarEventValue &&
          other.summary == summary &&
          other.location == location &&
          other.description == description &&
          other.start == start &&
          other.end == end;

  @override
  int get hashCode => Object.hash(
    CalendarEventValue,
    summary,
    location,
    description,
    start,
    end,
  );

  @override
  String toString() => 'CalendarEventValue(${summary ?? ''})';
}

/// An ISBN (EAN-13 starting with 978/979).
final class IsbnValue extends ParsedValue {
  const IsbnValue(this.isbn);

  final String isbn;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is IsbnValue && other.isbn == isbn;

  @override
  int get hashCode => Object.hash(IsbnValue, isbn);

  @override
  String toString() => 'IsbnValue($isbn)';
}

/// A retail product code (EAN/UPC).
final class ProductValue extends ParsedValue {
  const ProductValue(this.productCode);

  final String productCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductValue && other.productCode == productCode;

  @override
  int get hashCode => Object.hash(ProductValue, productCode);

  @override
  String toString() => 'ProductValue($productCode)';
}

/// Structured access to [Barcode.value].
extension BarcodeParsing on Barcode {
  /// Parses [value] on each call; see [ParsedValue.parse].
  ParsedValue get parsed => ParsedValue.parse(value, format: format);
}

final RegExp _bareEmail = RegExp(r'^[^@\s:;,]+@[^@\s:;,]+\.[^@\s:;,.]+$');

// --- DoCoMo-style payloads (WIFI: / MECARD: / MATMSG:) ---
// "KEY:value;KEY:value;;" with backslash escaping inside values.

List<MapEntry<String, String>> _docomoFields(String body) {
  final segments = <String>[];
  final buffer = StringBuffer();
  var escaped = false;
  for (var i = 0; i < body.length; i++) {
    final char = body[i];
    if (escaped) {
      buffer.write(char);
      escaped = false;
    } else if (char == r'\') {
      escaped = true;
    } else if (char == ';') {
      segments.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  if (buffer.isNotEmpty) segments.add(buffer.toString());

  final fields = <MapEntry<String, String>>[];
  for (final segment in segments) {
    final colon = segment.indexOf(':');
    if (colon <= 0) continue;
    fields.add(
      MapEntry(
        segment.substring(0, colon).trim().toUpperCase(),
        segment.substring(colon + 1),
      ),
    );
  }
  return fields;
}

ParsedValue? _parseWifi(String value) {
  String? ssid;
  String? password;
  String? security;
  var hidden = false;
  for (final field in _docomoFields(value.substring('WIFI:'.length))) {
    switch (field.key) {
      case 'S':
        ssid = field.value;
      case 'P':
        password = field.value;
      case 'T':
        security = field.value;
      case 'H':
        hidden = field.value.toLowerCase() == 'true';
    }
  }
  if (ssid == null || ssid.isEmpty) return null;
  return WifiValue(
    ssid: ssid,
    password: (password == null || password.isEmpty) ? null : password,
    security: switch (security?.toUpperCase()) {
      'WEP' => .wep,
      'WPA' || 'WPA2' || 'WPA3' || 'SAE' => .wpa,
      _ => .open,
    },
    hidden: hidden,
  );
}

ParsedValue? _parseMeCard(String value) {
  String? name;
  String? note;
  final phones = <String>[];
  final emails = <String>[];
  final urls = <String>[];
  final addresses = <String>[];
  for (final field in _docomoFields(value.substring('MECARD:'.length))) {
    if (field.value.isEmpty) continue;
    switch (field.key) {
      case 'N':
        name = _cleanComponents(field.value.split(',')).join(' ');
      case 'TEL':
      case 'TEL-AV':
        phones.add(field.value);
      case 'EMAIL':
        emails.add(field.value);
      case 'URL':
        urls.add(field.value);
      case 'ADR':
        addresses.add(field.value);
      case 'NOTE':
        note = field.value;
    }
  }
  if (name == null &&
      note == null &&
      phones.isEmpty &&
      emails.isEmpty &&
      urls.isEmpty &&
      addresses.isEmpty) {
    return null;
  }
  return ContactValue(
    name: name,
    phones: List.unmodifiable(phones),
    emails: List.unmodifiable(emails),
    urls: List.unmodifiable(urls),
    addresses: List.unmodifiable(addresses),
    note: note,
  );
}

// --- Line-oriented payloads (vCard / iCalendar) ---

/// Joins continuation lines (leading space/tab) onto their preceding line.
List<String> _unfoldLines(String value) {
  final lines = <String>[];
  for (final line in value.split(RegExp(r'\r?\n'))) {
    if ((line.startsWith(' ') || line.startsWith('\t')) && lines.isNotEmpty) {
      lines[lines.length - 1] += line.substring(1);
    } else {
      lines.add(line);
    }
  }
  return lines;
}

/// Joins quoted-printable soft line breaks: a QUOTED-PRINTABLE property line
/// ending in '=' continues on the next line (vCard 2.1 folding).
List<String> _joinQpSoftBreaks(List<String> lines) {
  final joined = <String>[];
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (_isQuotedPrintableProperty(line)) {
      while (line.endsWith('=') &&
          i + 1 < lines.length &&
          !_qpPropertyBoundary.hasMatch(lines[i + 1])) {
        line = line.substring(0, line.length - 1) + lines[++i];
      }
    }
    joined.add(line);
  }
  return joined;
}

/// Property names are conventionally uppercase; requiring that keeps a QP
/// continuation starting with prose like `tel:` joinable, while a malformed
/// trailing '=' cannot swallow a following real property.
final RegExp _qpPropertyBoundary = RegExp(r'^[A-Z][A-Z0-9-]*[;:]');

bool _isQuotedPrintableProperty(String line) {
  final colon = line.indexOf(':');
  return colon > 0 &&
      line.substring(0, colon).toUpperCase().contains('QUOTED-PRINTABLE');
}

/// Decodes `=XX` escapes as UTF-8 bytes; invalid escapes stay literal.
String _decodeQuotedPrintable(String input) {
  final bytes = <int>[];
  for (var i = 0; i < input.length; i++) {
    final unit = input.codeUnitAt(i);
    if (unit > 0xFF) return input; // Already decoded text, not QP ASCII.
    if (unit == 0x3D /* = */ && i + 2 < input.length) {
      final high = _hexDigit(input.codeUnitAt(i + 1));
      final low = _hexDigit(input.codeUnitAt(i + 2));
      if (high >= 0 && low >= 0) {
        bytes.add(high << 4 | low);
        i += 2;
        continue;
      }
    }
    bytes.add(unit);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

int _hexDigit(int unit) {
  if (unit >= 0x30 && unit <= 0x39) return unit - 0x30;
  if (unit >= 0x41 && unit <= 0x46) return unit - 0x37;
  if (unit >= 0x61 && unit <= 0x66) return unit - 0x57;
  return -1;
}

/// Splits a property line into its uppercased name (parameters and group
/// prefix dropped) and raw value, or returns null for a non-property line.
(String, String)? _splitProperty(String line) {
  final colon = line.indexOf(':');
  if (colon <= 0) return null;
  var left = line.substring(0, colon);
  final dot = left.indexOf('.');
  if (dot >= 0) left = left.substring(dot + 1);
  final semicolon = left.indexOf(';');
  if (semicolon >= 0) left = left.substring(0, semicolon);
  return (left.trim().toUpperCase(), line.substring(colon + 1));
}

/// Splits [input] on unescaped semicolons (vCard component separator).
List<String> _splitComponents(String input) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var escaped = false;
  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    if (escaped) {
      buffer.write(char == 'n' || char == 'N' ? '\n' : char);
      escaped = false;
    } else if (char == r'\') {
      escaped = true;
    } else if (char == ';') {
      parts.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  parts.add(buffer.toString());
  return parts;
}

String _unescapeText(String input) => _splitComponents(input).join(';');

/// Trims each component and drops the empty ones.
Iterable<String> _cleanComponents(Iterable<String> parts) =>
    parts.map((part) => part.trim()).where((part) => part.isNotEmpty);

ParsedValue? _parseVCard(String value) {
  String? name;
  String? fallbackName;
  String? organization;
  String? title;
  String? note;
  final phones = <String>[];
  final emails = <String>[];
  final urls = <String>[];
  final addresses = <String>[];
  for (final line in _joinQpSoftBreaks(_unfoldLines(value))) {
    final property = _splitProperty(line);
    if (property == null) continue;
    var (prop, raw) = property;
    if (raw.isEmpty) continue;
    if (_isQuotedPrintableProperty(line)) {
      raw = _decodeQuotedPrintable(raw);
    }
    switch (prop) {
      case 'FN':
        name = _unescapeText(raw);
      case 'N':
        // family;given;additional;prefix;suffix → display order.
        final parts = _cleanComponents(
          _splitComponents(raw),
        ).toList(growable: false);
        if (parts.length >= 2) {
          fallbackName = '${parts[1]} ${parts[0]}';
        } else if (parts.isNotEmpty) {
          fallbackName = parts[0];
        }
      case 'ORG':
        organization = _cleanComponents(_splitComponents(raw)).join(' ');
      case 'TITLE':
        title = _unescapeText(raw);
      case 'TEL':
        phones.add(_unescapeText(raw));
      case 'EMAIL':
        emails.add(_unescapeText(raw));
      case 'URL':
        urls.add(_unescapeText(raw));
      case 'ADR':
        final address = _cleanComponents(_splitComponents(raw)).join(', ');
        if (address.isNotEmpty) addresses.add(address);
      case 'NOTE':
        note = _unescapeText(raw);
    }
  }
  name ??= fallbackName;
  if (name == null &&
      organization == null &&
      title == null &&
      note == null &&
      phones.isEmpty &&
      emails.isEmpty &&
      urls.isEmpty &&
      addresses.isEmpty) {
    return null;
  }
  return ContactValue(
    name: name,
    organization: organization,
    title: title,
    phones: List.unmodifiable(phones),
    emails: List.unmodifiable(emails),
    urls: List.unmodifiable(urls),
    addresses: List.unmodifiable(addresses),
    note: note,
  );
}

ParsedValue? _parseCalendar(String value) {
  final lines = _unfoldLines(value);
  final begin = lines.indexWhere(
    (line) => line.trim().toUpperCase().startsWith('BEGIN:VEVENT'),
  );
  if (begin < 0) return null;
  var end = lines.indexWhere(
    (line) => line.trim().toUpperCase().startsWith('END:VEVENT'),
    begin,
  );
  if (end < 0) end = lines.length;

  String? summary;
  String? location;
  String? description;
  DateTime? start;
  DateTime? endTime;
  for (final line in lines.sublist(begin + 1, end)) {
    final property = _splitProperty(line);
    if (property == null) continue;
    final (prop, raw) = property;
    if (raw.isEmpty) continue;
    switch (prop) {
      case 'SUMMARY':
        summary = _unescapeText(raw);
      case 'LOCATION':
        location = _unescapeText(raw);
      case 'DESCRIPTION':
        description = _unescapeText(raw);
      case 'DTSTART':
        start = _parseICalDate(raw);
      case 'DTEND':
        endTime = _parseICalDate(raw);
    }
  }
  return CalendarEventValue(
    summary: summary,
    location: location,
    description: description,
    start: start,
    end: endTime,
  );
}

final RegExp _icalDate = RegExp(
  r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$',
);

DateTime? _parseICalDate(String raw) {
  final match = _icalDate.firstMatch(raw.trim());
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final hour = int.parse(match[4] ?? '0');
  final minute = int.parse(match[5] ?? '0');
  final second = int.parse(match[6] ?? '0');
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31 ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  final date = match[7] == 'Z'
      ? DateTime.utc(year, month, day, hour, minute, second)
      : DateTime(year, month, day, hour, minute, second);
  // DateTime normalizes calendar-impossible dates (Feb 30 → Mar 2); reject
  // them instead of returning a shifted date.
  if (date.month != month || date.day != day) return null;
  return date;
}

// --- URI-style payloads ---

ParsedValue? _parseMatmsg(String value) {
  String? address;
  String? subject;
  String? body;
  for (final field in _docomoFields(value.substring('MATMSG:'.length))) {
    switch (field.key) {
      case 'TO':
        address = field.value;
      case 'SUB':
        subject = field.value;
      case 'BODY':
        body = field.value;
    }
  }
  if (address == null || address.isEmpty) return null;
  return EmailValue(address: address, subject: subject, body: body);
}

/// Case-insensitive lookup in a URI's query parameters.
String? _queryParameter(Uri uri, String key) {
  try {
    for (final entry in uri.queryParameters.entries) {
      if (entry.key.toLowerCase() == key) return entry.value;
    }
  } on FormatException {
    // Malformed percent-encoding; treat as absent.
  }
  return null;
}

ParsedValue? _parseMailto(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.path.isEmpty) return null;
  return EmailValue(
    address: uri.path,
    subject: _queryParameter(uri, 'subject'),
    body: _queryParameter(uri, 'body'),
  );
}

ParsedValue? _parseSmsTo(String value) {
  final rest = value.substring('SMSTO:'.length);
  final colon = rest.indexOf(':');
  final number = colon < 0 ? rest : rest.substring(0, colon);
  if (number.isEmpty) return null;
  return SmsValue(
    number: number,
    message: colon < 0 ? null : rest.substring(colon + 1),
  );
}

ParsedValue? _parseSmsUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.path.isEmpty) return null;
  return SmsValue(number: uri.path, message: _queryParameter(uri, 'body'));
}

ParsedValue? _parseTel(String value) {
  var number = value.substring('TEL:'.length);
  final cut = number.indexOf(RegExp(r'[;?]'));
  if (cut >= 0) number = number.substring(0, cut);
  try {
    number = Uri.decodeComponent(number);
  } on ArgumentError {
    // Malformed percent-encoding; keep the raw digits.
  }
  // Percent-encoded separators decode into new ones; cut those too.
  final decodedCut = number.indexOf(RegExp(r'[;?]'));
  if (decodedCut >= 0) number = number.substring(0, decodedCut);
  if (number.isEmpty) return null;
  return PhoneValue(number);
}

ParsedValue? _parseGeo(String value) {
  var rest = value.substring('GEO:'.length);
  String? query;
  final questionMark = rest.indexOf('?');
  if (questionMark >= 0) {
    for (final param in rest.substring(questionMark + 1).split('&')) {
      if (param.toLowerCase().startsWith('q=')) {
        try {
          query = Uri.decodeQueryComponent(param.substring(2));
        } on ArgumentError {
          query = param.substring(2);
        }
        break;
      }
    }
    rest = rest.substring(0, questionMark);
  }
  final semicolon = rest.indexOf(';');
  if (semicolon >= 0) rest = rest.substring(0, semicolon);
  final coordinates = rest.split(',');
  if (coordinates.length < 2) return null;
  final latitude = double.tryParse(coordinates[0]);
  final longitude = double.tryParse(coordinates[1]);
  if (latitude == null || longitude == null) return null;
  return GeoValue(
    latitude: latitude,
    longitude: longitude,
    altitude: coordinates.length > 2 ? double.tryParse(coordinates[2]) : null,
    query: query,
  );
}

ParsedValue? _parseUrlTo(String value) {
  final rest = value.substring('URLTO:'.length);
  final colon = rest.indexOf(':');
  if (colon < 0 || colon == rest.length - 1) return null;
  final title = rest.substring(0, colon);
  return UrlValue(
    url: rest.substring(colon + 1),
    title: title.isEmpty ? null : title,
  );
}
