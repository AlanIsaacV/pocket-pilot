/// Representa una fila parseada del CSV de importación.
///
/// Todos los campos son texto plano (nombres humanos, no UUIDs).
/// La resolución a IDs se hace en una fase posterior con [MappingDictionary].
class CsvTransactionRow {
  final String date;
  final String type;
  final double amount;
  final String currencyCode;
  final String accountName;
  final String? destinationAccountName;
  final String? categoryName;
  final List<String> tagNames;
  final String notes;
  final String nature;
  final int installmentsCount;

  const CsvTransactionRow({
    required this.date,
    required this.type,
    required this.amount,
    required this.currencyCode,
    required this.accountName,
    this.destinationAccountName,
    this.categoryName,
    required this.tagNames,
    required this.notes,
    this.nature = '',
    this.installmentsCount = 1,
  });
}
