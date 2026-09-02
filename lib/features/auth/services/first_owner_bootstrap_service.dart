import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/licensing/activation/activation_state_repository.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/db/tables/owner_bootstrap_tables.dart';
import 'package:yalla_accounts/features/auth/services/password_hasher.dart';

class FirstOwnerBootstrapRequest {
  const FirstOwnerBootstrapRequest({
    required this.ownerName,
    required this.password,
    required this.workshopName,
    required this.workshopAddress,
    required this.country,
    required this.province,
    required this.city,
    required this.street,
    required this.phone,
    this.email = '',
    this.logoPath,
  });

  final String ownerName;
  final String password;
  final String email;
  final String workshopName;
  final String workshopAddress;
  final String country;
  final String province;
  final String city;
  final String street;
  final String phone;
  final String? logoPath;
}

class FirstOwnerBootstrapResult {
  const FirstOwnerBootstrapResult({
    required this.ownerUserId,
    required this.recoveryCode,
  });

  final String ownerUserId;
  final String recoveryCode;
}

class FirstOwnerBootstrapException implements Exception {
  const FirstOwnerBootstrapException(this.message);
  final String message;

  @override
  String toString() => 'FirstOwnerBootstrapException: $message';
}

typedef BootstrapDatabaseProvider = Future<Database> Function();

class FirstOwnerBootstrapService {
  FirstOwnerBootstrapService({
    BootstrapDatabaseProvider? databaseProvider,
    ActivationStateRepository? activationStateRepository,
  })  : _databaseProvider = databaseProvider ?? (() => DBService.database),
        _activationStateRepository = activationStateRepository;

  final BootstrapDatabaseProvider _databaseProvider;
  final ActivationStateRepository? _activationStateRepository;

  Future<FirstOwnerBootstrapResult> createFirstOwner(
    FirstOwnerBootstrapRequest request,
  ) async {
    final ownerName = request.ownerName.trim();
    final workshopName = request.workshopName.trim();
    final phone = request.phone.trim();
    if (ownerName.isEmpty || workshopName.isEmpty || phone.isEmpty) {
      throw const FirstOwnerBootstrapException(
        'Owner name, workshop name and phone are required.',
      );
    }
    final passwordError = _validatePassword(request.password);
    if (passwordError != null) {
      throw FirstOwnerBootstrapException(passwordError);
    }

    final db = await _databaseProvider();
    await OwnerBootstrapTables.ensure(db);
    final activation = _activationStateRepository ??
        ActivationStateRepository(databaseProvider: _databaseProvider);
    if (!await activation.hasUsableActivationForCurrentInstallation()) {
      throw const FirstOwnerBootstrapException(
        'Verified online activation is required before First Owner setup.',
      );
    }

    final identityRows = await db.query(
      'installation_identity',
      where: 'singleton_id = 1',
      limit: 1,
    );
    if (identityRows.length != 1) {
      throw const FirstOwnerBootstrapException('Device identity is missing.');
    }
    final identity = identityRows.single;
    final organizationId = identity['organization_id']!.toString();
    final installationId = identity['installation_id']!.toString();
    final deviceId = identity['device_id']!.toString();

    final activationRows = await db.query(
      'license_activation_state',
      where: 'singleton_id = 1 AND status = ? AND organization_id = ? '
          'AND installation_id = ? AND device_id = ?',
      whereArgs: ['ACTIVE', organizationId, installationId, deviceId],
      limit: 1,
    );
    if (activationRows.length != 1) {
      throw const FirstOwnerBootstrapException(
        'Active activation receipt is missing.',
      );
    }
    final activationRow = Map<String, Object?>.from(activationRows.single);
    final activationId = activationRow['activation_id']?.toString() ?? '';
    if (activationId.isEmpty) {
      throw const FirstOwnerBootstrapException('Activation ID is missing.');
    }

    final recoveryCode = _generateRecoveryCode();
    final ownerUserId = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final countryCode = _countryCode(request.country);

    await db.transaction((txn) async {
      final stateRows = await txn.query(
        'owner_bootstrap_state',
        where: 'singleton_id = 1 AND organization_id = ?',
        whereArgs: [organizationId],
        limit: 1,
      );
      if (stateRows.length != 1 || stateRows.single['status'] != 'PENDING') {
        throw const FirstOwnerBootstrapException(
          'First Owner bootstrap has already been completed.',
        );
      }

      final userCount = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM users WHERE organization_id = ?',
              [organizationId],
            ),
          ) ??
          0;
      if (userCount != 0) {
        throw const FirstOwnerBootstrapException(
          'First Owner bootstrap requires an empty user set.',
        );
      }

      final liveActivation = await txn.query(
        'license_activation_state',
        where: 'singleton_id = 1 AND status = ? AND organization_id = ? '
            'AND installation_id = ? AND device_id = ? AND activation_id = ?',
        whereArgs: [
          'ACTIVE',
          organizationId,
          installationId,
          deviceId,
          activationId,
        ],
        limit: 1,
      );
      if (liveActivation.length != 1 ||
          liveActivation.single['signed_license_envelope_json']?.toString() !=
              activationRow['signed_license_envelope_json']?.toString() ||
          liveActivation.single['verification_keyset_json']?.toString() !=
              activationRow['verification_keyset_json']?.toString()) {
        throw const FirstOwnerBootstrapException(
          'Activation state changed during First Owner bootstrap.',
        );
      }

      await txn.insert('users', {
        'id': ownerUserId,
        'organization_id': organizationId,
        'name': ownerName,
        'email': request.email.trim(),
        'password': PasswordHasher.hash(request.password),
        'role': 'owner',
        'status': 'active',
        'created_at': now,
        'is_owner': 1,
        'must_change_password': 0,
        'failed_login_count': 0,
        'locked_until': null,
        'password_changed_at': now,
        'recovery_code_hash': PasswordHasher.hash(recoveryCode),
        'recovery_code_used': 0,
        'workshop_logo_path': request.logoPath,
        'workshop_address': request.workshopAddress.trim(),
        'country': request.country.trim(),
        'province': request.province.trim(),
        'city': request.city.trim(),
        'street': request.street.trim(),
        'workshop_phone': phone,
        'phone_numbers': phone,
      });

      final workshopRow = <String, Object?>{
        'id': 1,
        'organization_id': organizationId,
        'workshopName': workshopName,
        'address': request.workshopAddress.trim(),
        'city': request.city.trim(),
        'phone1': phone,
        'logoPath': request.logoPath,
        'updated_at': now,
        'country_code': countryCode,
      };
      final currentWorkshop = await txn.query(
        'workshop_settings',
        columns: ['id'],
        where: 'id = 1',
        limit: 1,
      );
      if (currentWorkshop.isEmpty) {
        workshopRow['created_at'] = now;
        await txn.insert('workshop_settings', workshopRow);
      } else {
        workshopRow.remove('id');
        await txn.update('workshop_settings', workshopRow, where: 'id = 1');
      }

      await txn.update(
        'organizations',
        {
          'display_name': workshopName,
          'country_code': countryCode,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [organizationId],
      );

      final changed = await txn.update(
        'owner_bootstrap_state',
        {
          'status': 'COMPLETED',
          'owner_user_id': ownerUserId,
          'activation_id': activationId,
          'completed_at': now,
          'updated_at': now,
        },
        where: 'singleton_id = 1 AND organization_id = ? AND status = ?',
        whereArgs: [organizationId, 'PENDING'],
      );
      if (changed != 1) {
        throw const FirstOwnerBootstrapException(
          'Could not close First Owner bootstrap atomically.',
        );
      }
    });

    await OwnerBootstrapTables.validate(db);
    return FirstOwnerBootstrapResult(
      ownerUserId: ownerUserId,
      recoveryCode: recoveryCode,
    );
  }

  static String? _validatePassword(String password) {
    if (password.length < 10) {
      return 'Password must contain at least 10 characters.';
    }
    final hasLetter = RegExp(r'[A-Za-z\u0600-\u06FF]').hasMatch(password);
    final hasDigit = RegExp(r'\d').hasMatch(password);
    if (!hasLetter || !hasDigit) {
      return 'Password must contain letters and numbers.';
    }
    return null;
  }

  static String _generateRecoveryCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    String block() => List.generate(
          4,
          (_) => chars[random.nextInt(chars.length)],
        ).join();
    return 'YA-${block()}-${block()}';
  }

  static String _countryCode(String country) {
    switch (country.trim()) {
      case 'فلسطين':
        return 'PS';
      case 'الأردن':
        return 'JO';
      case 'مصر':
        return 'EG';
      case 'سوريا':
        return 'SY';
      default:
        return 'PS';
    }
  }
}
