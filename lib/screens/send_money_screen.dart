import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

// builds a USSD code and opens the phone app with pre-filled string
class SendMoneyScreen extends StatefulWidget {
  final VoidCallback? onSuccess;

  const SendMoneyScreen({super.key, this.onSuccess});

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen> {
  bool _isPhone = true;
  final _recipientController = TextEditingController();
  final _amountController = TextEditingController();

  static const _quickAmounts = [500, 1000, 2000, 5000, 10000];

  @override
  void dispose() {
    _recipientController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  String? _buildUssd() {
    final recipient = _recipientController.text;
    final amount = _amountController.text;
    if (recipient.isEmpty || amount.isEmpty) return null;

    final sanitizedRecipient = recipient.replaceAll(RegExp(r'\s+'), '');
    final sanitizedAmount = amount.replaceAll(RegExp(r'[^0-9]'), '');
    return _isPhone
        ? '*182*1*1*$sanitizedRecipient*$sanitizedAmount#'
        : '*182*8*1*$sanitizedRecipient*$sanitizedAmount#';
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleSend() async {
    if (_recipientController.text.isEmpty || _amountController.text.isEmpty) {
      _showSnack('Please enter recipient and amount');
      return;
    }

    final ussd = _buildUssd();
    if (ussd == null) return;

    if (Platform.isAndroid) {
      final status = await Permission.phone.request();
      if (!status.isGranted) {
        _showSnack('Cannot place calls without permission.');
        return;
      }
    }

    final uri = Uri.parse('tel:${Uri.encodeComponent(ussd)}');
    try {
      final launched = await launchUrl(uri);
      if (launched) {
        widget.onSuccess?.call();
      } else {
        _showSnack('Unable to open dialer for USSD code');
      }
    } catch (e) {
      _showSnack('Failed to initiate transaction');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(20),
          children: [
            Text('Send Money', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
            SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(10)),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  Expanded(child: _ToggleButton(label: 'Phone Number', active: _isPhone, onTap: () => setState(() => _isPhone = true))),
                  Expanded(child: _ToggleButton(label: 'Merchant Code', active: !_isPhone, onTap: () => setState(() => _isPhone = false))),
                ],
              ),
            ),
            SizedBox(height: 12),
            Text(_isPhone ? 'Phone Number' : 'Merchant Code', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            SizedBox(height: 6),
            TextField(
              controller: _recipientController,
              keyboardType: _isPhone ? TextInputType.phone : TextInputType.text,
              decoration: InputDecoration(
                hintText: _isPhone ? '078XXXXXXXX' : 'Enter merchant code',
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                contentPadding: EdgeInsets.all(12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            SizedBox(height: 12),
            Text('Amount (RWF)', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            SizedBox(height: 6),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '0',
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                contentPadding: EdgeInsets.all(12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final q in _quickAmounts)
                  GestureDetector(
                    onTap: () => setState(() => _amountController.text = q.toString()),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(8)),
                      child: Text(q.toString(), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _handleSend,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFFBBF24),
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Send', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToggleButton({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10),
        color: active ? Color(0xFFFBBF24) : Colors.transparent,
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: active ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
