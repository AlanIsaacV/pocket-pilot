// ============================================================
// CsvImportService — lógica de negocio para importación de CSV
// ============================================================
//
// Orquesta las fases de extracción y transformación del pipeline
// de importación. Stateless: recibe dependencias por constructor.

import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/features/csv_import/domain/csv_extraction_result.dart';
import 'package:pocket_pilot/src/features/csv_import/domain/csv_insert_batch.dart';
import 'package:pocket_pilot/src/features/csv_import/domain/csv_transaction_row.dart';
import 'package:pocket_pilot/src/features/csv_import/domain/mapping_dictionary.dart';

class CsvImportService {
  final Uuid _uuid;

  CsvImportService({required Uuid uuid}) : _uuid = uuid;

  // Encabezados esperados (en orden).
  static const _expectedHeaders = [
    'date',
    'type',
    'amount',
    'currency',
    'account',
    'destination_account',
    'category',
    'tags',
    'notes',
  ];

  static const _validTypes = {'EXPENSE', 'INCOME', 'TRANSFER'};
  static const _validNatures = {
    'required',
    'obligation',
    'lifestyle',
    'active',
    'passive',
    'windfall',
  };

  // ----------------------------------------------------------
  // Fase 1: Extracción
  // ----------------------------------------------------------

  /// Parsea el contenido CSV y extrae las entidades únicas.
  ///
  /// Valida encabezados, tipos, y campos requeridos por fila.
  /// Lanza [FormatException] con número de fila si algo es inválido.
  CsvExtractionResult parseAndExtract(String csvContent) {
    final parsed = const CsvDecoder().convert(csvContent);

    if (parsed.isEmpty) {
      throw const FormatException('El archivo CSV está vacío.');
    }

    // Validar encabezados.
    final headers = parsed.first
        .map((h) => h.toString().trim().toLowerCase())
        .toList();
    if (headers.length < _expectedHeaders.length) {
      throw FormatException(
        'Encabezados incompletos. Esperados: ${_expectedHeaders.join(", ")}',
      );
    }
    for (var i = 0; i < _expectedHeaders.length; i++) {
      if (headers[i] != _expectedHeaders[i]) {
        throw FormatException(
          'Encabezado inválido en columna ${i + 1}: '
          'esperado "${_expectedHeaders[i]}", encontrado "${headers[i]}".',
        );
      }
    }

    // Detect optional columns by name.
    int? natureCol;
    int? installmentsCol;
    for (var i = _expectedHeaders.length; i < headers.length; i++) {
      if (headers[i] == 'nature') natureCol = i;
      if (headers[i] == 'installments_count') installmentsCol = i;
    }

    final rows = <CsvTransactionRow>[];
    final accountNames = <String>{};
    final categoryNames = <String>{};
    final tagNames = <String>{};

    for (var i = 1; i < parsed.length; i++) {
      final raw = parsed[i];
      final rowNum = i + 1; // 1-indexed, header es fila 1

      if (raw.length < _expectedHeaders.length) {
        throw FormatException(
          'Fila $rowNum: esperadas ${_expectedHeaders.length} columnas, '
          'encontradas ${raw.length}.',
        );
      }

      final type = raw[1].toString().trim().toUpperCase();
      if (!_validTypes.contains(type)) {
        throw FormatException(
          'Fila $rowNum: tipo inválido "$type". '
          'Valores permitidos: ${_validTypes.join(", ")}.',
        );
      }

      final accountName = raw[4].toString().trim();
      if (accountName.isEmpty) {
        throw FormatException('Fila $rowNum: el campo "account" es requerido.');
      }

      final destAccountRaw = raw[5].toString().trim();
      String? destinationAccountName;
      if (type == 'TRANSFER') {
        if (destAccountRaw.isEmpty) {
          throw FormatException(
            'Fila $rowNum: las transferencias requieren "destination_account".',
          );
        }
        destinationAccountName = destAccountRaw;
      }

      final categoryRaw = raw[6].toString().trim();
      final categoryName = categoryRaw.isEmpty ? null : categoryRaw;

      final tagsRaw = raw[7].toString().trim();
      final parsedTags = tagsRaw.isEmpty
          ? <String>[]
          : tagsRaw
                .split('|')
                .map((t) => t.trim())
                .where((t) => t.isNotEmpty)
                .toList();

      final amountRaw = raw[2].toString().trim();
      final amount = double.tryParse(amountRaw);
      if (amount == null) {
        throw FormatException('Fila $rowNum: monto inválido "$amountRaw".');
      }

      // Parse optional nature column.
      var nature = '';
      if (natureCol != null && raw.length > natureCol) {
        final rawNature = raw[natureCol].toString().trim().toLowerCase();
        if (rawNature.isNotEmpty && _validNatures.contains(rawNature)) {
          nature = rawNature;
        }
      }

      // Parse optional installments_count column.
      var installmentsCount = 1;
      if (installmentsCol != null && raw.length > installmentsCol) {
        final rawInstallments = raw[installmentsCol].toString().trim();
        if (rawInstallments.isNotEmpty) {
          final parsed = int.tryParse(rawInstallments);
          if (parsed == null || parsed < 1) {
            throw FormatException(
              'Fila $rowNum: installments_count inválido "$rawInstallments". '
              'Debe ser un entero positivo.',
            );
          }
          installmentsCount = parsed;
        }
      }

      rows.add(
        CsvTransactionRow(
          date: raw[0].toString().trim(),
          type: type,
          amount: amount,
          currencyCode: raw[3].toString().trim(),
          accountName: accountName,
          destinationAccountName: destinationAccountName,
          categoryName: categoryName,
          tagNames: parsedTags,
          notes: raw[8].toString().trim(),
          nature: nature,
          installmentsCount: installmentsCount,
        ),
      );

      // Recolectar nombres únicos.
      accountNames.add(accountName);
      if (destinationAccountName != null) {
        accountNames.add(destinationAccountName);
      }
      if (categoryName != null) {
        categoryNames.add(categoryName);
      }
      tagNames.addAll(parsedTags);
    }

    return CsvExtractionResult(
      rows: rows,
      uniqueAccountNames: accountNames,
      uniqueCategoryNames: categoryNames,
      uniqueTagNames: tagNames,
    );
  }

  // ----------------------------------------------------------
  // Fase 3: Transformación → CsvInsertBatch
  // ----------------------------------------------------------

  /// Transforma las filas parseadas en un batch listo para inserción.
  ///
  /// Usa [mapping] para resolver nombres a UUIDs.
  /// Lanza [StateError] si un nombre no tiene mapping.
  CsvInsertBatch buildInsertBatch(
    List<CsvTransactionRow> rows,
    MappingDictionary mapping,
  ) {
    final transactionMaps = <Map<String, dynamic>>[];
    final outboxEntries = <Map<String, dynamic>>[];
    final now = DateTime.now().toUtc().toIso8601String();

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowNum = i + 1;

      // --- Resolución de entidades ---
      final accountId = _resolveMapping(
        mapping.accountIdMap,
        row.accountName,
        'account',
        rowNum,
      );

      final String? categoryId;
      if (row.categoryName != null) {
        categoryId = _resolveMapping(
          mapping.categoryIdMap,
          row.categoryName!,
          'category',
          rowNum,
        );
      } else {
        categoryId = null;
      }

      final tagIds = row.tagNames
          .map((name) => _resolveMapping(mapping.tagIdMap, name, 'tag', rowNum))
          .toList();

      // --- Conversión de monto ---
      final amountCents = (row.amount * 100).round();

      // --- Generar maps según tipo ---
      if (row.type == 'TRANSFER') {
        final destAccountId = _resolveMapping(
          mapping.accountIdMap,
          row.destinationAccountName!,
          'destination_account',
          rowNum,
        );

        final outId = _uuid.v4();
        final inId = _uuid.v4();

        final sharedFields = <String, dynamic>{
          'category_id': categoryId,
          'template_id': null,
          'yield_id': null,
          'amount_cents': amountCents,
          'installments_count': row.installmentsCount,
          'nature': row.nature,
          'currency_code': row.currencyCode,
          'status': 'cleared',
          'source': 'import_csv',
          'tags': jsonEncode(tagIds),
          'description': row.notes,
          'date': row.date,
          'created_at': now,
          'updated_at': now,
        };

        final outMap = <String, dynamic>{
          ...sharedFields,
          'id': outId,
          'account_id': accountId,
          'linked_transaction_id': inId,
          'type': 'transfer_out',
        };

        final inMap = <String, dynamic>{
          ...sharedFields,
          'id': inId,
          'account_id': destAccountId,
          'linked_transaction_id': outId,
          'type': 'transfer_in',
        };

        transactionMaps.add(outMap);
        transactionMaps.add(inMap);
        outboxEntries.add(_buildOutboxEntry(outMap, tagIds));
        outboxEntries.add(_buildOutboxEntry(inMap, tagIds));
      } else {
        final id = _uuid.v4();
        final dbType = row.type == 'EXPENSE' ? 'expense' : 'income';

        final txMap = <String, dynamic>{
          'id': id,
          'account_id': accountId,
          'category_id': categoryId,
          'linked_transaction_id': null,
          'template_id': null,
          'yield_id': null,
          'type': dbType,
          'amount_cents': amountCents,
          'installments_count': row.installmentsCount,
          'nature': row.nature,
          'currency_code': row.currencyCode,
          'status': 'cleared',
          'source': 'import_csv',
          'tags': jsonEncode(tagIds),
          'description': row.notes,
          'date': row.date,
          'created_at': now,
          'updated_at': now,
        };

        transactionMaps.add(txMap);
        outboxEntries.add(_buildOutboxEntry(txMap, tagIds));
      }
    }

    return CsvInsertBatch(
      transactionMaps: transactionMaps,
      outboxEntries: outboxEntries,
    );
  }

  // ----------------------------------------------------------
  // Helpers privados
  // ----------------------------------------------------------

  /// Busca [name] en [map]. Lanza [StateError] si no existe.
  String _resolveMapping(
    Map<String, String> map,
    String name,
    String entityType,
    int rowNum,
  ) {
    final id = map[name];
    if (id == null) {
      throw StateError(
        'Fila $rowNum: no se encontró mapping para $entityType "$name".',
      );
    }
    return id;
  }

  /// Construye una entrada para sync_outbox.
  ///
  /// El payload usa formato servidor: tags como `List<String>` en vez de
  /// JSON string. Se omiten created_at, retry_count y last_error
  /// (SQLite usa sus defaults).
  Map<String, dynamic> _buildOutboxEntry(
    Map<String, dynamic> txMap,
    List<String> tagIds,
  ) {
    final serverPayload = Map<String, dynamic>.from(txMap)..['tags'] = tagIds;
    return {
      'entity_type': 'transaction',
      'entity_id': txMap['id'] as String,
      'operation': 'upsert',
      'payload': jsonEncode(serverPayload),
    };
  }
}
