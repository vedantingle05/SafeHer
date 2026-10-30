/// SafeHer Widget Tests
/// Basic smoke tests for core widgets and services.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher/models/data_models.dart';

void main() {
  group('Data Models', () {
    test('UserModel parses from JSON correctly', () {
      final json = {
        '_id': '123',
        'name': 'Jane Doe',
        'email': 'jane@example.com',
        'phone': '+919876543210',
        'emergencyContacts': [
          {'_id': 'c1', 'name': 'Mom', 'phone': '+919876543210', 'relation': 'Mother'},
        ],
      };

      final user = UserModel.fromJson(json);

      expect(user.id, '123');
      expect(user.name, 'Jane Doe');
      expect(user.email, 'jane@example.com');
      expect(user.phone, '+919876543210');
      expect(user.emergencyContacts.length, 1);
      expect(user.emergencyContacts.first.name, 'Mom');
      expect(user.emergencyContacts.first.relation, 'Mother');
    });

    test('AlertModel parses from JSON correctly', () {
      final json = {
        '_id': 'alert123',
        'userId': 'user456',
        'type': 'scream',
        'location': {'latitude': 18.5204, 'longitude': 73.8567},
        'status': 'triggered',
        'confidence': 0.92,
        'evidenceUrls': ['https://example.com/audio.mp3'],
        'createdAt': '2026-04-14T10:30:00Z',
      };

      final alert = AlertModel.fromJson(json);

      expect(alert.id, 'alert123');
      expect(alert.type, 'scream');
      expect(alert.typeLabel, 'Scream Detected');
      expect(alert.typeEmoji, '🔊');
      expect(alert.location.latitude, 18.5204);
      expect(alert.location.longitude, 73.8567);
      expect(alert.confidence, 0.92);
      expect(alert.evidenceUrls.length, 1);
      expect(alert.status, 'triggered');
    });

    test('AlertLocation generates correct Maps link', () {
      final location = AlertLocation(latitude: 18.5204, longitude: 73.8567);
      expect(
        location.mapsLink,
        'https://maps.google.com/?q=18.5204,73.8567',
      );
    });

    test('EmergencyContact serializes to JSON', () {
      final contact = EmergencyContact(
        name: 'Mom',
        phone: '+919876543210',
        relation: 'Mother',
      );

      final json = contact.toJson();
      expect(json['name'], 'Mom');
      expect(json['phone'], '+919876543210');
      expect(json['relation'], 'Mother');
    });
  });

  group('Alert Types', () {
    test('All alert types have labels and emojis', () {
      final types = ['scream', 'fall', 'panic_button', 'emotion', 'manual'];
      for (final type in types) {
        final alert = AlertModel.fromJson({
          '_id': 'test',
          'userId': 'test',
          'type': type,
          'location': {'latitude': 0, 'longitude': 0},
          'status': 'triggered',
          'createdAt': DateTime.now().toIso8601String(),
        });

        expect(alert.typeLabel.isNotEmpty, true, reason: 'Missing label for $type');
        expect(alert.typeEmoji.isNotEmpty, true, reason: 'Missing emoji for $type');
      }
    });
  });
}
