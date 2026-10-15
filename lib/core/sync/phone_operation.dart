class PhoneOperation {
  const PhoneOperation({
    required this.id,
    required this.scope,
    required this.customerId,
    required this.phone,
    required this.basePhone,
    required this.createdAt,
    required this.status,
    required this.attempts,
    required this.nextAt,
    this.error,
    this.kind,
    this.leaseToken,
    this.force = false,
  });
  final String id, scope, phone, basePhone, status;
  final int customerId, createdAt, attempts, nextAt;
  final String? error, kind, leaseToken;
  final bool force;
  factory PhoneOperation.fromRow(Map<String, Object?> r) => PhoneOperation(
    id: r['operation_id'] as String,
    scope: r['scope'] as String,
    customerId: r['customer_id'] as int,
    phone: r['phone'] as String,
    basePhone: r['base_phone'] as String,
    createdAt: r['created_at'] as int,
    status: r['status'] as String,
    attempts: r['attempts'] as int,
    nextAt: r['next_at'] as int,
    error: r['last_error'] as String?,
    kind: r['error_kind'] as String?,
    leaseToken: r['lease_token'] as String?,
    force: r['force_write'] == 1,
  );
}
