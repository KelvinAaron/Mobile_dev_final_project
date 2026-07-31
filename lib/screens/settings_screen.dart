import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

class SettingsScreen extends StatefulWidget {
  final Database? db;
  final String userPhone;
  final VoidCallback? onSave;
  final Future<int> Function() onSyncNow;
  final VoidCallback onLogout;
  final bool isLightMode;
  final ValueChanged<bool> onLightModeChanged;

  const SettingsScreen({
    super.key,
    required this.db,
    required this.userPhone,
    this.onSave,
    required this.onSyncNow,
    required this.onLogout,
    required this.isLightMode,
    required this.onLightModeChanged,
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Budget limits saved successfully')));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync failed. Please try again.')));
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Log out'),
        content: Text('You will need to sign in again on this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Log out')),
        ],
      ),
    );
    if (confirmed == true) widget.onLogout();
  }

  Widget _limitInput(String label, String key) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controllers[key],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: '0 = no limit',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                Text('RWF', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Center(child: Text('Loading settings...', style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant))),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Text('Settings', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(16),
              margin: EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Icon(widget.isLightMode ? Icons.light_mode : Icons.dark_mode),
                title: Text(widget.isLightMode ? 'Light mode' : 'Dark mode'),
                subtitle: Text('Tap to switch between light and dark themes'),
                value: widget.isLightMode,
                onChanged: widget.onLightModeChanged,
              ),
            ),
            Text('Budget Limits', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
            SizedBox(height: 8),
            Text('Set monthly spending limits (0 = no limit)', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            SizedBox(height: 24),
            Container(
              padding: EdgeInsets.all(16),
              margin: EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Overall Spending', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
                  SizedBox(height: 16),
                  _limitInput('Monthly General Limit', 'general'),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.all(16),
              margin: EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Category Limits', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
                  SizedBox(height: 16),
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
                backgroundColor: Color(0xFFFBBF24),
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: EdgeInsets.symmetric(vertical: 16),
                minimumSize: Size.fromHeight(56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Save Limits', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            SizedBox(height: 24),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Color(0xFF17263A) : Color(0xFFDBEAFE),
                borderRadius: BorderRadius.circular(12),
                border: Border(left: BorderSide(color: Color(0xFF0284C7), width: 4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: isDark ? Color(0xFF93C5FD) : Color(0xFF0C4A6E),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'How it works',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Color(0xFF93C5FD) : Color(0xFF0C4A6E),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Set a limit for any category (enter 0 or leave blank for no limit)\n'
                    '• If you exceed a limit, an alert will appear at the top of the app\n'
                    '• Limits apply only to monthly spending\n'
                    '• Check your spending on the Spending tab',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Color(0xFFBFDBFE) : Color(0xFF0C4A6E),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cloud Sync', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
                  SizedBox(height: 4),
                  Text(
                    'Finmo backs up automatically once a day when you open the app. You can also sync manually.',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _isSyncing ? null : _handleSyncNow,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      minimumSize: Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(_isSyncing ? 'Syncing...' : 'Sync now'),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            OutlinedButton(
              onPressed: _handleLogout,
              style: OutlinedButton.styleFrom(
                foregroundColor: Color(0xFFDC2626),
                side: BorderSide(color: Color(0xFFDC2626)),
                padding: EdgeInsets.symmetric(vertical: 14),
                minimumSize: Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Log out'),
            ),
          ],
        ),
      ),
    );
  }
}
