class Borrower {
  int? id;
  String borrowerCode;
  String name;
  String phone;
  String? address;
  String? notes;

  // Transient fields computed at query time
  double totalBalance;
  int loanCount;

  Borrower({
    this.id,
    required this.borrowerCode,
    required this.name,
    required this.phone,
    this.address,
    this.notes,
    this.totalBalance = 0.0,
    this.loanCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'borrower_code': borrowerCode,
      'name': name,
      'phone': phone,
      'address': address,
      'notes': notes,
    };
  }

  factory Borrower.fromMap(Map<String, dynamic> map) {
    return Borrower(
      id: map['id'],
      borrowerCode: map['borrower_code'] ?? '',
      name: map['name'],
      phone: map['phone'],
      address: map['address'],
      notes: map['notes'],
    );
  }
}
