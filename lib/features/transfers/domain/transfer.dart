enum TransferStatus { daily, archived }

TransferStatus _parseStatus(String s) =>
    s == 'archived' ? TransferStatus.archived : TransferStatus.daily;

String transferStatusToDb(TransferStatus s) =>
    s == TransferStatus.archived ? 'archived' : 'daily';

class Transfer {
  const Transfer({
    required this.id,
    required this.ownerId,
    required this.companyId,
    required this.exchangeId,
    required this.beneficiaryName,
    required this.beneficiaryAccountCompany,
    required this.beneficiaryCode,
    required this.amount,
    required this.reference,
    required this.status,
    required this.createdAt,
    required this.archivedAt,
    required this.createdByEmployeeId,
  });

  final String id;
  final String ownerId;
  final String companyId;
  final String exchangeId;
  final String beneficiaryName;
  final String? beneficiaryAccountCompany;
  final String? beneficiaryCode;
  final double amount;
  final String reference;
  final TransferStatus status;
  final DateTime createdAt;
  final DateTime? archivedAt;
  /// Sub-user (employee) who authored this row, or null when the admin
  /// created it directly. Stamped by `record_transfer` from
  /// `current_employee_id()` (see migration 0025).
  final String? createdByEmployeeId;

  factory Transfer.fromJson(Map<String, dynamic> json) => Transfer(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String,
        companyId: json['company_id'] as String,
        exchangeId: json['exchange_id'] as String,
        beneficiaryName: json['beneficiary_name'] as String,
        beneficiaryAccountCompany:
            json['beneficiary_account_company'] as String?,
        beneficiaryCode: json['beneficiary_code'] as String?,
        amount: (json['amount'] as num).toDouble(),
        reference: json['reference'] as String,
        status: _parseStatus(json['status'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        archivedAt: json['archived_at'] == null
            ? null
            : DateTime.parse(json['archived_at'] as String),
        createdByEmployeeId: json['created_by_employee_id'] as String?,
      );
}
