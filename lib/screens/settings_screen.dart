import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

class SettingsScreen extends StatefulWidget {
  final Database? db;
  final String userPhone;
  final VoidCallback? onSave;
  final Future<int> Function() onSyncNow;
  final VoidCallback onLogout;

  const SettingsScreen({
    super.key,
    required this.db,
    required this.userPhone,
    this.onSave,
    required this.onSyncNow,
    required this.onLogout,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;
  bool _isSyncing = false;

  static const _limitColumns = {
    'general': 'General_Spending_Limit',
    'moneyTransfer': 'Money_Transfer_Limit',
    'bankTransfer': 'Bank_Transfer_Limit',
    'merchant': 'Merchant_Limit',
    'bundles': 'Bundles_Limit',
    'utilities': 'Utilities_Limit',
    'agents': 'Agent_Limit',
    'others': 'Others_Limit',
  };

  final Map<String, TextEditingController> _controllers = {
    for (final key in _limitColumns.keys) key: TextEditingController(text: '0'),
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final db = widget.db;
    if (db == null || widget.userPhone.isEmpty) return;

    setState(() => _isLoading = true);
    final rows = await db.query('Settings', where: 'Phone_Number = ?', whereArgs: [widget.userPhone], limit: 1);
    if (rows.isNotEmpty) {
      final settings = rows.first;
      for (final entry in _limitColumns.entries) {
        _controllers[entry.key]!.text = ((settings[entry.value] as num?) ?? 0).toStringAsFixed(0);
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveLimits() async {
    final db = widget.db;
    if (db == null || widget.userPhone.isEmpty) return;

    final row = <String, Object?>{
      'Settings_Id': 'SETTINGS-${widget.userPhone}',
      'Phone_Number': widget.userPhone,
    };
    for (final entry in _limitColumns.entries) {
      row[entry.value] = int.tryParse(_controllers[entry.key]!.text) ?? 0;
    }

    await db.insert('Settings', row, conflictAlgorithm: ConflictAlgorithm.replace);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Budget limits saved successfully')));
    widget.onSave?.call();
  }

  Future<void> _handleSyncNow() async {
    setState(() => _isSyncing = true);
    try {
      final count = await widget.onSyncNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Synced $count transaction(s) to the cloud.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sync failed. Please try again.')));
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('You will need to sign in again on this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log out')),
        ],
      ),
    );
    if (confirmed == true) widget.onLogout();
  }

  Widget _limitInput(String label, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controllers[key],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: '0 = no limit',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const Text('RWF', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFFEF3C7),
        body: SafeArea(
          child: Center(child: Text('Loading settings...', style: TextStyle(fontSize: 16, color: Color(0xFF6B7280)))),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFEF3C7),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            const Text('Budget Limits', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
            const SizedBox(height: 8),
            const Text('Set monthly spending limits (0 = no limit)', style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Overall Spending', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
                  const SizedBox(height: 16),
                  _limitInput('Monthly General Limit', 'general'),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Category Limits', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
                  const SizedBox(height: 16),
                  _limitInput('Money Transfers', 'moneyTransfer'),
                  _limitInput('Bank Transfers', 'bankTransfer'),
                  _limitInput('Merchant Payments', 'merchant'),
                  _limitInput('Bundles (Airtime/Data)', 'bundles'),
                  _limitInput('Utilities', 'utilities'),
                  _limitInput('Agents', 'agents'),
                  _limitInput('Others', 'others'),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: _saveLimits,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFBBF24),
                foregroundColor: const Color(0xFF1F2937),
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Save Limits', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFDBEAFE),
                borderRadius: BorderRadius.circular(12),
                border: const Border(left: BorderSide(color: Color(0xFF0284C7), width: 4)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ℹ️ How it works', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0C4A6E))),
                  SizedBox(height: 8),
                  Text(
                    '• Set a limit for any category (enter 0 or leave blank for no limit)\n'
                    '• If you exceed a limit, an alert will appear at the top of the app\n'
                    '• Limits apply only to monthly spending\n'
                    '• Check your spending on the Spending tab',
                    style: TextStyle(fontSize: 12, color: Color(0xFF0C4A6E), height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Cloud Sync', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
                  const SizedBox(height: 4),
                  const Text(
                    'Finmo backs up automatically once a day when you open the app. You can also sync manually.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _isSyncing ? null : _handleSyncNow,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(_isSyncing ? 'Syncing...' : 'Sync now'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _handleLogout,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFDC2626)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Log out'),
            ),
          ],
        ),
      ),
    );
  }
}
