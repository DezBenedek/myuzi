import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../services/toast.dart';
import '../../widgets/widgets.dart';

Future<void> showBillingDetailsSheet(
  BuildContext context, {
  required ApiClient api,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BillingDetailsSheet(api: api),
  );
}

class BillingDetailsSheet extends StatefulWidget {
  const BillingDetailsSheet({super.key, required this.api});

  final ApiClient api;

  @override
  State<BillingDetailsSheet> createState() => _BillingDetailsSheetState();
}

class _BillingDetailsSheetState extends State<BillingDetailsSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _taxId = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _postalCode = TextEditingController();

  String _type = 'individual';
  bool _loading = true;
  bool _saving = false;
  bool _isOwner = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _name.dispose();
    _taxId.dispose();
    _address.dispose();
    _city.dispose();
    _postalCode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final status = await widget.api.billingStatus();
      final details = status.billing;
      if (!mounted) return;
      if (details != null) {
        _type = details.billingType;
        _name.text = details.billingName;
        _taxId.text = details.taxId;
        _address.text = details.addressLine1;
        _city.text = details.city;
        _postalCode.text = details.postalCode;
      }
      setState(() {
        _isOwner = status.isOwner;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'A számlázási adatok betöltése sikertelen.';
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.saveBillingDetails(
        billingType: _type,
        billingName: _name.text.trim(),
        taxId: _taxId.text.trim(),
        addressLine1: _address.text.trim(),
        city: _city.text.trim(),
        postalCode: _postalCode.text.trim(),
      );
      if (!mounted) return;
      showAppToast(context, 'Számlázási adatok mentve');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Mentés sikertelen');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final disabled = _loading || !_isOwner || _saving;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _loading
            ? const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Számlázási adatok',
                        style: t.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      if (!_isOwner)
                        Text(
                          'A számlázási adatokat csak a család tulajdonosa módosíthatja.',
                          style: t.textTheme.bodyMedium,
                        )
                      else
                        Text(
                          'Ezeket az adatokat használjuk a számlázáshoz.',
                          style: t.textTheme.bodyMedium,
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(color: t.colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _type,
                        decoration: const InputDecoration(
                          labelText: 'Számlázás',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'individual',
                            child: Text('Magánszemély'),
                          ),
                          DropdownMenuItem(
                            value: 'company',
                            child: Text('Cég'),
                          ),
                        ],
                        onChanged: disabled
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _type = value);
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _name,
                        enabled: !disabled,
                        decoration: const InputDecoration(
                          labelText: 'Számlázási név',
                        ),
                        validator: (value) =>
                            (value == null || value.trim().length < 2)
                            ? 'Add meg a számlázási nevet'
                            : null,
                      ),
                      if (_type == 'company') ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _taxId,
                          enabled: !disabled,
                          decoration: const InputDecoration(
                            labelText: 'Adószám',
                          ),
                          validator: (value) =>
                              (value == null || value.trim().length < 5)
                              ? 'Cégnél az adószám kötelező'
                              : null,
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _address,
                        enabled: !disabled,
                        decoration: const InputDecoration(labelText: 'Cím'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Add meg a címet'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _postalCode,
                              enabled: !disabled,
                              decoration: const InputDecoration(
                                labelText: 'Irányítószám',
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Kötelező'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _city,
                              enabled: !disabled,
                              decoration: const InputDecoration(
                                labelText: 'Város',
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Kötelező'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      BigButton(
                        label: _saving ? 'Mentés…' : 'Mentés',
                        icon: Icons.save_outlined,
                        onPressed: disabled ? null : _save,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
