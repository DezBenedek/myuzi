class BillingDetails {
  const BillingDetails({
    required this.billingType,
    required this.billingName,
    required this.taxId,
    required this.addressLine1,
    required this.city,
    required this.postalCode,
    required this.country,
  });

  final String billingType;
  final String billingName;
  final String taxId;
  final String addressLine1;
  final String city;
  final String postalCode;
  final String country;

  bool get isCompany => billingType == 'company';

  bool get isComplete =>
      billingName.trim().length >= 2 &&
      addressLine1.trim().isNotEmpty &&
      city.trim().isNotEmpty &&
      postalCode.trim().isNotEmpty &&
      (!isCompany || taxId.trim().length >= 5);

  factory BillingDetails.fromJson(Map<String, dynamic> json) {
    return BillingDetails(
      billingType: json['billingType'] as String? ?? 'individual',
      billingName: json['billingName'] as String? ?? '',
      taxId: json['taxId'] as String? ?? '',
      addressLine1: json['addressLine1'] as String? ?? '',
      city: json['city'] as String? ?? '',
      postalCode: json['postalCode'] as String? ?? '',
      country: json['country'] as String? ?? 'HU',
    );
  }
}

class BillingInvoice {
  const BillingInvoice({
    required this.id,
    required this.number,
    required this.created,
    required this.amountPaid,
    required this.currency,
    required this.status,
    required this.downloadUrl,
  });

  final String id;
  final String? number;
  final DateTime created;
  final int amountPaid;
  final String currency;
  final String? status;
  final String? downloadUrl;

  factory BillingInvoice.fromJson(Map<String, dynamic> json) {
    final createdSeconds = (json['created'] as num?)?.toInt() ?? 0;
    return BillingInvoice(
      id: json['id'] as String? ?? '',
      number: json['number'] as String?,
      created: DateTime.fromMillisecondsSinceEpoch(createdSeconds * 1000),
      amountPaid: (json['amountPaid'] as num?)?.toInt() ?? 0,
      currency: json['currency'] as String? ?? 'huf',
      status: json['status'] as String?,
      downloadUrl: json['downloadUrl'] as String?,
    );
  }

  String get displayNumber => number?.isNotEmpty == true ? number! : id;

  String get displayAmount {
    final zeroDecimal = {
      'bif',
      'clp',
      'djf',
      'gnf',
      'jpy',
      'kmf',
      'krw',
      'mga',
      'pyg',
      'rwf',
      'ugx',
      'vnd',
      'vuv',
      'xaf',
      'xof',
      'xpf',
      'huf',
    }.contains(currency.toLowerCase());
    final amount = (zeroDecimal ? amountPaid : amountPaid / 100)
        .toStringAsFixed(0);
    return '$amount ${currency.toUpperCase()}';
  }
}
