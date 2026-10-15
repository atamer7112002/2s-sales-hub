String odooText(dynamic value) => value is String ? value : '';
String relationName(dynamic value) =>
    value is List && value.length > 1 ? odooText(value[1]) : '';

class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.phone = '',
    this.city = '',
    this.email = '',
    this.address = '',
    this.offline = false,
    this.syncStatus = 'synced',
    this.syncError,
  });
  final int id;
  final bool offline;
  final String syncStatus;
  final String? syncError;
  Customer withSync(String phone, String status, String? error) => Customer(
    id: id,
    name: name,
    phone: phone,
    city: city,
    email: email,
    address: address,
    offline: offline,
    syncStatus: status,
    syncError: error,
  );
  Customer get cached => Customer(
    id: id,
    name: name,
    phone: phone,
    city: city,
    email: email,
    address: address,
    offline: true,
    syncStatus: syncStatus,
    syncError: syncError,
  );
  final String name, phone, city, email, address;
  factory Customer.fromOdoo(Map<String, dynamic> row) => Customer(
    id: row['id'] as int,
    name: odooText(row['name']),
    phone: odooText(row['phone']),
    city: odooText(row['city']),
    email: odooText(row['email']),
    address: [
      odooText(row['street']),
      odooText(row['street2']),
      odooText(row['city']),
      relationName(row['state_id']),
      odooText(row['zip']),
      relationName(row['country_id']),
    ].where((s) => s.isNotEmpty).join(', '),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'city': city,
    'email': email,
    'address': address,
  };
  factory Customer.fromJson(Map<String, dynamic> r) => Customer(
    id: r['id'],
    name: r['name'],
    phone: r['phone'],
    city: r['city'],
    email: r['email'],
    address: r['address'],
  );
}

class CustomerPage {
  const CustomerPage(this.items, {this.offline = false, this.hasMore = false});
  final List<Customer> items;
  final bool offline, hasMore;
}

abstract interface class CustomerRepository {
  Future<CustomerPage> list({String query = '', int offset = 0});
  Future<Customer> get(int id, {bool localOnly = false});
  Future<void> updatePhone(int id, String phone);
}

String? validatePhone(String value) =>
    value.trim().isEmpty ||
        (RegExp(r'^[+0-9() .-]{5,30}$').hasMatch(value.trim()) &&
            RegExp(r'\d').allMatches(value).length >= 5)
    ? null
    : 'Enter a valid phone number (5–30 characters).';
