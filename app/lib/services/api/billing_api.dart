part of 'client.dart';

mixin BillingApi on ApiClientBase {
  Future<({Family? family, bool isOwner, BillingDetails? billing})>
  billingStatus() async {
    final res = await _send(
      (uri) => _client.get(uri, headers: _headers()),
      path: '/api/billing/status',
    );
    final body = await _json(res);
    final familyJson = body['family'];
    final billingJson = body['billing'];
    return (
      family: familyJson is Map
          ? Family.fromJson(Map<String, dynamic>.from(familyJson))
          : null,
      isOwner: body['isOwner'] == true,
      billing: billingJson is Map
          ? BillingDetails.fromJson(Map<String, dynamic>.from(billingJson))
          : null,
    );
  }

  Future<BillingDetails> saveBillingDetails({
    required String billingType,
    required String billingName,
    required String taxId,
    required String addressLine1,
    required String city,
    required String postalCode,
    String country = 'HU',
  }) async {
    final res = await _send(
      (uri) => _client.patch(
        uri,
        headers: _headers(),
        body: jsonEncode({
          'billingType': billingType,
          'billingName': billingName,
          'taxId': taxId,
          'addressLine1': addressLine1,
          'city': city,
          'postalCode': postalCode,
          'country': country,
        }),
      ),
      path: '/api/billing/details',
    );
    final body = await _json(res);
    return BillingDetails.fromJson(
      Map<String, dynamic>.from(body['billing'] as Map),
    );
  }

  Future<List<BillingInvoice>> billingInvoices() async {
    final res = await _send(
      (uri) => _client.get(uri, headers: _headers()),
      path: '/api/billing/invoices',
    );
    final body = await _json(res);
    return ((body['invoices'] as List?) ?? [])
        .whereType<Map>()
        .map((item) => BillingInvoice.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }
}
