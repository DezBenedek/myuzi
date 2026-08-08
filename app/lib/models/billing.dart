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
    required this.issuedAt,
    required this.amount,
    required this.currency,
    required this.periodLabel,
    required this.downloadPath,
  });

  final String id;
  final String? number;
  final DateTime issuedAt;
  final int amount;
  final String currency;
  final String? periodLabel;
  final String? downloadPath;

  factory BillingInvoice.fromJson(Map<String, dynamic> json) {
    final issuedAt =
        DateTime.tryParse(json['issuedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return BillingInvoice(
      id: json['id'] as String? ?? '',
      number: json['number'] as String?,
      issuedAt: issuedAt,
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      currency: json['currency'] as String? ?? 'huf',
      periodLabel: json['periodLabel'] as String?,
      downloadPath: json['downloadPath'] as String?,
    );
  }

  String get displayNumber => number?.isNotEmpty == true ? number! : id;

  String get displayAmount {
    return '$amount ${currency.toUpperCase()}';
  }
}
