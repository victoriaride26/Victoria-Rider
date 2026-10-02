import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vtrides/features/ride/data/support_contacts.dart';
import 'package:vtrides/features/ride/presentation/widgets/support_contacts_sheet.dart';

void main() {
  group('parseSupportContacts — GET /users/support/emergency', () {
    // Shape from the OpenAPI spec: rows live in `data: [ … ]` and the phone
    // key is `number` (not `phone` / `mobileNumber`).
    const response = {
      'success': true,
      'data': [
        {
          'id': '123e4567-e89b-12d3-a456-426614174000',
          'name': 'Emergency Services Abuja',
          'number': '112',
          'isActive': true,
        },
        {
          'id': '2',
          'name': 'Police',
          'number': '199',
          'isActive': true,
        },
      ],
    };

    test('reads every row of the list with its `number`', () {
      final contacts = parseSupportContacts(response);

      expect(contacts, hasLength(2));
      expect(contacts.first.name, 'Emergency Services Abuja');
      expect(contacts.first.phone, '112');
      expect(contacts.last.phone, '199');
      expect(contacts.first.whatsappNumber, isNull);
      expect(contacts.first.location, isNull);
    });

    test('drops inactive rows', () {
      final contacts = parseSupportContacts({
        'success': true,
        'data': [
          {'name': 'Active', 'number': '112', 'isActive': true},
          {'name': 'Retired', 'number': '999', 'isActive': false},
        ],
      });

      expect(contacts.map((c) => c.name), ['Active']);
    });

    test('never throws on a malformed payload', () {
      expect(parseSupportContacts(null), isEmpty);
      expect(parseSupportContacts('boom'), isEmpty);
      expect(parseSupportContacts({'success': false}), isEmpty);
      expect(parseSupportContacts({'data': [42, null, 'x']}), isEmpty);
      expect(parseSupportContacts({'data': {'nope': 1}}), isEmpty);
    });
  });

  group('parseSupportContacts — GET /users/support/customer-service', () {
    // Different shape: `mobileNumber`, `whatsappNumber` and `location`.
    const response = {
      'success': true,
      'data': [
        {
          'id': '123e4567-e89b-12d3-a456-426614174000',
          'name': 'Support Center Abuja',
          'location': 'Wuse 2, Abuja',
          'mobileNumber': '+2348012345678',
          'whatsappNumber': '+2348012345678',
          'isActive': true,
        },
      ],
    };

    test('reads name, location, mobile and whatsapp', () {
      final contact = parseSupportContacts(response).single;

      expect(contact.name, 'Support Center Abuja');
      expect(contact.location, 'Wuse 2, Abuja');
      expect(contact.phone, '+2348012345678');
      expect(contact.whatsappNumber, '+2348012345678');
    });

    test('accepts a single object instead of a list', () {
      final contact = parseSupportContacts({
        'data': {'name': 'Support', 'mobileNumber': '0800'},
      }).single;

      expect(contact.phone, '0800');
    });

    test('keeps a contact that only has a name', () {
      final contact = parseSupportContacts({
        'data': [
          {'name': 'Support Center'},
        ],
      }).single;

      expect(contact.hasName, isTrue);
      expect(contact.phone, isNull);
      expect(contact.isEmpty, isFalse);
    });
  });

  group('SupportContactsSheet', () {
    Future<void> pumpSheet(
      WidgetTester tester,
      SupportContactsSheet sheet,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: sheet)),
      );
    }

    testWidgets('emergency modal lists the name, number and Call action',
        (tester) async {
      await pumpSheet(
        tester,
        const SupportContactsSheet(
          title: 'Emergency',
          contacts: [
            SupportContact(name: 'Emergency Services Abuja', phone: '112'),
          ],
        ),
      );

      expect(find.text('Emergency'), findsOneWidget);
      expect(find.text('Emergency Services Abuja'), findsOneWidget);
      expect(find.text('112'), findsOneWidget);
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('customer care modal lists location, mobile and WhatsApp',
        (tester) async {
      await pumpSheet(
        tester,
        const SupportContactsSheet(
          title: 'Customer Care',
          contacts: [
            SupportContact(
              name: 'Support Center Abuja',
              location: 'Wuse 2, Abuja',
              phone: '+2348012345678',
              whatsappNumber: '+2348012345678',
            ),
          ],
        ),
      );

      expect(find.text('Wuse 2, Abuja'), findsOneWidget);
      expect(find.text('+2348012345678'), findsNWidgets(2));
      expect(find.text('WhatsApp'), findsOneWidget);
    });

    testWidgets('empty state stays in the modal', (tester) async {
      await pumpSheet(
        tester,
        const SupportContactsSheet(title: 'Emergency', contacts: []),
      );

      expect(
        find.text('No Emergency contacts are available right now. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('fetch error stays in the modal', (tester) async {
      await pumpSheet(
        tester,
        const SupportContactsSheet(
          title: 'Customer Care',
          contacts: [],
          errorMessage: 'Could not load Customer Care contacts right now. Please try again.',
        ),
      );

      expect(find.textContaining('Could not load Customer Care'), findsOneWidget);
    });

    testWidgets('Close dismisses the modal', (tester) async {
      await pumpSheet(
        tester,
        const SupportContactsSheet(title: 'Emergency', contacts: []),
      );

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(SupportContactsSheet), findsNothing);
    });
  });
}
