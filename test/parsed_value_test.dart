import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner_view/qr_scanner_view.dart';

void main() {
  ParsedValue parse(String value, {BarcodeFormat format = .unknown}) =>
      ParsedValue.parse(value, format: format);

  group('retail formats', () {
    test('EAN-13 starting with 978/979 is an ISBN', () {
      expect(
        parse('9784101010014', format: .ean13),
        const IsbnValue('9784101010014'),
      );
      expect(
        parse('9791234567896', format: .ean13),
        const IsbnValue('9791234567896'),
      );
    });

    test('other EAN/UPC values are products', () {
      expect(
        parse('4901234567894', format: .ean13),
        const ProductValue('4901234567894'),
      );
      expect(parse('12345670', format: .ean8), const ProductValue('12345670'));
      expect(
        parse('012345678905', format: .upcA),
        const ProductValue('012345678905'),
      );
      expect(parse('01234565', format: .upcE), const ProductValue('01234565'));
    });

    test('an ISBN-looking string in a QR stays text', () {
      expect(parse('9784101010014'), const TextValue('9784101010014'));
    });
  });

  group('wifi', () {
    test('parses fields and unescapes', () {
      expect(
        parse(r'WIFI:T:WPA;S:My\;Net\\Home;P:p\:ss;H:true;;'),
        const WifiValue(
          ssid: r'My;Net\Home',
          password: 'p:ss',
          security: .wpa,
          hidden: true,
        ),
      );
    });

    test('maps security variants and defaults to open', () {
      expect(
        parse('WIFI:S:a;T:WEP;;'),
        const WifiValue(ssid: 'a', security: .wep),
      );
      expect(
        parse('WIFI:S:a;T:WPA2;;'),
        const WifiValue(ssid: 'a', security: .wpa),
      );
      expect(parse('WIFI:S:a;T:nopass;;'), const WifiValue(ssid: 'a'));
      expect(parse('wifi:s:a;;'), const WifiValue(ssid: 'a'));
    });

    test('falls back to text without an SSID', () {
      expect(parse('WIFI:T:WPA;P:secret;;'), isA<TextValue>());
    });
  });

  group('contact', () {
    test('parses MECARD', () {
      final contact = parse(
        'MECARD:N:Yamada,Sakura;TEL:+81312345678;EMAIL:s@example.com;'
        'ADR:Tokyo;NOTE:friend;;',
      );
      expect(
        contact,
        const ContactValue(
          name: 'Yamada Sakura',
          phones: ['+81312345678'],
          emails: ['s@example.com'],
          addresses: ['Tokyo'],
          note: 'friend',
        ),
      );
    });

    test('empty MECARD falls back to text', () {
      expect(parse('MECARD:;;'), isA<TextValue>());
    });

    test('parses vCard with folding, params and escapes', () {
      final contact = parse(
        [
          'BEGIN:VCARD',
          'VERSION:3.0',
          'FN:Sakura',
          '  Yamada',
          'N:Yamada;Sakura;;;',
          'ORG:Example\\, Inc.;R&D',
          'TITLE:Engineer',
          'TEL;TYPE=CELL:+81312345678',
          'EMAIL:s@example.com',
          'item1.URL:https://example.com',
          'ADR;TYPE=WORK:;;1-2-3 Chiyoda;Tokyo;;100-0001;Japan',
          'NOTE:line1\\nline2',
          'END:VCARD',
        ].join('\r\n'),
      );
      expect(
        contact,
        const ContactValue(
          name: 'Sakura Yamada',
          organization: 'Example, Inc. R&D',
          title: 'Engineer',
          phones: ['+81312345678'],
          emails: ['s@example.com'],
          urls: ['https://example.com'],
          addresses: ['1-2-3 Chiyoda, Tokyo, 100-0001, Japan'],
          note: 'line1\nline2',
        ),
      );
    });

    test('vCard N is the fallback when FN is absent', () {
      final contact =
          parse('BEGIN:VCARD\nN:Yamada;Sakura\nEND:VCARD') as ContactValue;
      expect(contact.name, 'Sakura Yamada');
    });

    test('vCard decodes quoted-printable values and soft line breaks', () {
      final contact =
          parse(
                [
                  'BEGIN:VCARD',
                  'VERSION:2.1',
                  'N;ENCODING=QUOTED-PRINTABLE;CHARSET=UTF-8:=E5=B1=B1=E7=94=B0;=E3=82=B5=',
                  '=E3=83=A9',
                  'END:VCARD',
                ].join('\r\n'),
              )
              as ContactValue;
      expect(contact.name, 'サラ 山田');
    });

    test(
      'vCard QP value with a malformed trailing = keeps the next property',
      () {
        final contact =
            parse(
                  [
                    'BEGIN:VCARD',
                    'VERSION:2.1',
                    'NOTE;ENCODING=QUOTED-PRINTABLE:partial=',
                    'TEL:+123456',
                    'END:VCARD',
                  ].join('\r\n'),
                )
                as ContactValue;
        expect(contact.phones, ['+123456']);
      },
    );
  });

  group('calendar event', () {
    test('parses a VEVENT inside a VCALENDAR', () {
      final event = parse(
        [
          'BEGIN:VCALENDAR',
          'BEGIN:VEVENT',
          'SUMMARY:Meeting\\, sync',
          'LOCATION:Room 1',
          'DESCRIPTION:Agenda',
          'DTSTART:20260102T030405Z',
          'DTEND;VALUE=DATE:20260103',
          'END:VEVENT',
          'END:VCALENDAR',
        ].join('\n'),
      );
      expect(
        event,
        CalendarEventValue(
          summary: 'Meeting, sync',
          location: 'Room 1',
          description: 'Agenda',
          start: DateTime.utc(2026, 1, 2, 3, 4, 5),
          end: DateTime(2026, 1, 3),
        ),
      );
    });

    test('invalid dates parse as null fields', () {
      final event =
          parse('BEGIN:VEVENT\nSUMMARY:x\nDTSTART:20261301T000000\nEND:VEVENT')
              as CalendarEventValue;
      expect(event.summary, 'x');
      expect(event.start, isNull);
    });

    test('calendar-impossible dates parse as null instead of rolling over', () {
      final event =
          parse('BEGIN:VEVENT\nSUMMARY:x\nDTSTART:20260230T000000\nEND:VEVENT')
              as CalendarEventValue;
      expect(event.start, isNull);
    });

    test('a VCALENDAR without VEVENT falls back to text', () {
      expect(parse('BEGIN:VCALENDAR\nEND:VCALENDAR'), isA<TextValue>());
    });
  });

  group('email', () {
    test('parses mailto with query parameters', () {
      expect(
        parse('mailto:a@example.com?subject=Hi%20there&body=Yo'),
        const EmailValue(
          address: 'a@example.com',
          subject: 'Hi there',
          body: 'Yo',
        ),
      );
    });

    test('mailto without a recipient falls back to text', () {
      expect(parse('mailto:'), isA<TextValue>());
      expect(parse('mailto:?subject=Hi'), isA<TextValue>());
    });

    test('parses MATMSG', () {
      expect(
        parse('MATMSG:TO:a@example.com;SUB:Hello;BODY:World;;'),
        const EmailValue(
          address: 'a@example.com',
          subject: 'Hello',
          body: 'World',
        ),
      );
      expect(parse('MATMSG:SUB:no recipient;;'), isA<TextValue>());
    });

    test('recognizes a bare address', () {
      expect(
        parse('user@example.com'),
        const EmailValue(address: 'user@example.com'),
      );
      expect(parse('not an email'), isA<TextValue>());
      expect(parse('a@b'), isA<TextValue>());
    });
  });

  group('phone and sms', () {
    test('parses tel and strips parameters', () {
      expect(
        parse('tel:+81-3-1234-5678;ext=5'),
        const PhoneValue('+81-3-1234-5678'),
      );
      expect(parse('TEL:'), isA<TextValue>());
      expect(parse('tel:+1%3B555'), const PhoneValue('+1'));
    });

    test('parses SMSTO and sms URIs', () {
      expect(
        parse('SMSTO:+819012345678:hello'),
        const SmsValue(number: '+819012345678', message: 'hello'),
      );
      expect(
        parse('SMSTO:+819012345678'),
        const SmsValue(number: '+819012345678'),
      );
      expect(
        parse('sms:+819012345678?body=hi'),
        const SmsValue(number: '+819012345678', message: 'hi'),
      );
      expect(parse('SMSTO::no number'), isA<TextValue>());
    });
  });

  group('geo', () {
    test('parses coordinates, altitude and query', () {
      expect(
        parse('geo:35.6586,139.7454,12;u=10?q=Tokyo%20Tower'),
        const GeoValue(
          latitude: 35.6586,
          longitude: 139.7454,
          altitude: 12,
          query: 'Tokyo Tower',
        ),
      );
      expect(
        parse('geo:35.0,139.0'),
        const GeoValue(latitude: 35.0, longitude: 139.0),
      );
    });

    test('falls back to text on malformed coordinates', () {
      expect(parse('geo:abc,def'), isA<TextValue>());
      expect(parse('geo:35.0'), isA<TextValue>());
    });
  });

  group('url', () {
    test('recognizes http/https case-insensitively', () {
      expect(
        parse('https://example.com/a?b=c'),
        const UrlValue(url: 'https://example.com/a?b=c'),
      );
      expect(
        parse('HTTP://EXAMPLE.COM'),
        const UrlValue(url: 'HTTP://EXAMPLE.COM'),
      );
    });

    test('parses URLTO bookmarks', () {
      expect(
        parse('URLTO:Example:http://example.com'),
        const UrlValue(url: 'http://example.com', title: 'Example'),
      );
      expect(
        parse('URLTO::http://example.com'),
        const UrlValue(url: 'http://example.com'),
      );
      expect(parse('URLTO:title only:'), isA<TextValue>());
    });
  });

  test('plain and empty strings are text', () {
    expect(parse('hello world'), const TextValue('hello world'));
    expect(parse(''), const TextValue(''));
  });

  test('Barcode.parsed uses value and format', () {
    const url = Barcode(value: 'https://example.com', format: .qr);
    expect(url.parsed, const UrlValue(url: 'https://example.com'));
    const isbn = Barcode(value: '9784101010014', format: .ean13);
    expect(isbn.parsed, const IsbnValue('9784101010014'));
  });

  test('parsed values support value equality', () {
    expect(parse('WIFI:S:a;;'), parse('WIFI:S:a;;'));
    expect(parse('WIFI:S:a;;'), isNot(parse('WIFI:S:b;;')));
    expect(parse('MECARD:TEL:1;;').hashCode, parse('MECARD:TEL:1;;').hashCode);
  });

  test('toString omits the wifi password', () {
    expect(
      parse('WIFI:S:net;P:secret;T:WPA;;').toString(),
      isNot(contains('secret')),
    );
  });

  group('additional parsing coverage', () {
    test('MMSTO and MMS map like their SMS counterparts', () {
      expect(
        parse('MMSTO:+81901:hey'),
        const SmsValue(number: '+81901', message: 'hey'),
      );
      expect(
        parse('MMS:+81901?body=hi'),
        const SmsValue(number: '+81901', message: 'hi'),
      );
    });

    test('an sms URI without a number falls back to text', () {
      expect(parse('sms:?body=hi'), isA<TextValue>());
    });

    test('WPA3 and SAE map to wpa security', () {
      expect(
        parse('WIFI:S:a;T:WPA3;;'),
        const WifiValue(ssid: 'a', security: .wpa),
      );
      expect(
        parse('WIFI:S:a;T:SAE;;'),
        const WifiValue(ssid: 'a', security: .wpa),
      );
    });

    test('an empty vCard falls back to text', () {
      expect(parse('BEGIN:VCARD\nEND:VCARD'), isA<TextValue>());
    });

    test('tel with malformed percent-encoding keeps the raw value', () {
      expect(parse('tel:%E0%A4'), const PhoneValue('%E0%A4'));
    });

    test('geo drops an unparseable altitude and keeps coordinates', () {
      expect(
        parse('geo:35.0,139.0,abc'),
        const GeoValue(latitude: 35.0, longitude: 139.0),
      );
    });

    test('geo with malformed percent-encoded query keeps the raw query', () {
      expect(
        parse('geo:0,0?q=%E0%A4'),
        const GeoValue(latitude: 0, longitude: 0, query: '%E0%A4'),
      );
    });

    test('an empty retail payload is text', () {
      expect(parse('', format: .ean13), const TextValue(''));
    });

    test('URLTO without a URL part falls back to text', () {
      expect(parse('URLTO:title only'), isA<TextValue>());
    });
  });
}
