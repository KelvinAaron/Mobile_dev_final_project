import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'components/budget_alert_overlay.dart';
import 'database/database.dart';
import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/overview_screen.dart';
import 'screens/send_money_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/spending_screen.dart';
import 'screens/transactions_screen.dart';
import 'services/auth_service.dart';
import 'services/sms_service.dart';
import 'services/sync_service.dart';
import 'utils/budget_utils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const FinmoApp());
}

enum _AppStage { loading, auth, onboarding, main }

const _lastSmsSyncPrefsKey = 'finmo_last_sms_sync';
const _lastCloudSyncPrefsKey = 'finmo_last_cloud_sync';
const _cloudSyncInterval = Duration(hours: 24);

class FinmoApp extends StatefulWidget {
  const FinmoApp({super.key});

  @override
  State<FinmoApp> createState() => _FinmoAppState();
}

class _FinmoAppState extends State<FinmoApp> with WidgetsBindingObserver {
  Database? _db;
  String? _userPhone;
  String? _uid;
  _AppStage _stage = _AppStage.loading;
  String _period = 'monthly';
  List<BudgetAlert> _budgetAlerts = [];
  bool _showBudgetAlert = false;
  int? _lastSyncAt;
  bool _isSyncingSms = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _stage == _AppStage.main) {
      _syncSmsIncremental();
    }
  }

  Future<void> _bootstrap() async {
    final db = await AppDatabase.instance.database;
    final prefs = await SharedPreferences.getInstance();
    _lastSyncAt = prefs.getInt(_lastSmsSyncPrefsKey);
    setState(() => _db = db);

    final firebaseUser = AuthService.instance.currentUser;
    if (firebaseUser == null) {
      setState(() => _stage = _AppStage.auth);
      return;
    }
    await _postAuthInit(firebaseUser.uid);
  }

  // Resolves the local user row for [uid] if this is a new device or a fresh sign-in after logout
  Future<void> _postAuthInit(String uid) async {
    final db = _db!;
    final localUserRows = await db.query('Users', where: 'Firebase_Uid = ?', whereArgs: [uid], limit: 1);

    String? phoneNumber;
    if (localUserRows.isEmpty) {
      phoneNumber = await SyncService.instance.pullCloudToLocal(db: db, uid: uid);
    } else {
      phoneNumber = localUserRows.first['Phone_Number'] as String?;
    }

    if (phoneNumber == null) {
      setState(() => _stage = _AppStage.auth);
      return;
    }

    _userPhone = phoneNumber;
    _uid = uid;

    final settingsRows = await db.query('Settings', where: 'Phone_Number = ?', whereArgs: [phoneNumber], limit: 1);
    if (settingsRows.isEmpty) {
      setState(() => _stage = _AppStage.onboarding);
      return;
    }

    setState(() => _stage = _AppStage.main);
    await _checkAndSetBudgetAlerts();
    await _syncSmsIncremental();
    await _triggerCloudSyncIfDue();
  }

  Future<void> _handleSignUp(String email, String phone, String password) async {
    final credential = await AuthService.instance.signUp(email: email, password: password);
    final uid = credential.user!.uid;
    final db = _db!;

    await db.insert('Users', {'Phone_Number': phone, 'Name': '', 'Firebase_Uid': uid, 'Amount': 0});
    _userPhone = phone;
    _uid = uid;
    await SyncService.instance.pushLocalToCloud(db: db, uid: uid, phoneNumber: phone);

    setState(() => _stage = _AppStage.onboarding);
  }

  Future<void> _handleSignIn(String email, String password) async {
    final credential = await AuthService.instance.signIn(email: email, password: password);
    await _postAuthInit(credential.user!.uid);
    if (_userPhone == null) {
      throw Exception('No account data found for this login. Please sign up.');
    }
  }

  Future<void> _handleOnboardingComplete(OnboardingSettings settings) async {
    final db = _db!;
    final phone = _userPhone!;

    await db.insert(
      'Settings',
      {
        'Settings_Id': 'SETTINGS-$phone',
        'Phone_Number': phone,
        'General_Spending_Limit': settings.monthlyLimit,
        'Money_Transfer_Limit': 0,
        'Bank_Transfer_Limit': 0,
        'Merchant_Limit': 0,
        'Bundles_Limit': 0,
        'Utilities_Limit': 0,
        'Agent_Limit': 0,
        'Others_Limit': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (Platform.isAndroid) {
      await [Permission.sms, Permission.phone].request();
    }

    setState(() => _stage = _AppStage.main);
    await _checkAndSetBudgetAlerts();
    await _syncSmsFull();
    if (_uid != null) {
      await SyncService.instance.pushLocalToCloud(db: db, uid: _uid!, phoneNumber: phone);
    }
  }

  Future<void> _checkAndSetBudgetAlerts() async {
    if (_db == null || _userPhone == null) return;
    final alerts = await checkBudgetLimits(_db!, _userPhone!);
    if (!mounted) return;
    setState(() {
      _budgetAlerts = alerts;
      _showBudgetAlert = alerts.isNotEmpty;
    });
  }

  Future<void> _syncSmsFull() => _runSmsSync(incremental: false);

  Future<void> _syncSmsIncremental() => _runSmsSync(incremental: true);

  Future<void> _runSmsSync({required bool incremental}) async {
    if (_db == null || _userPhone == null || _isSyncingSms) return;
    _isSyncingSms = true;
    try {
      final minDate = incremental && _lastSyncAt != null ? _lastSyncAt! + 1 : 0;
      final result = await SmsService.instance.readMMoneyMessages(
        db: _db!,
        userPhone: _userPhone!,
        minDate: minDate,
      );
      if (result != null && (result.insertedCount > 0 || !incremental)) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_lastSmsSyncPrefsKey, result.maxMsgDate);
        _lastSyncAt = result.maxMsgDate;
      }
      await _checkAndSetBudgetAlerts();
    } finally {
      _isSyncingSms = false;
    }
  }

  Future<void> _triggerCloudSyncIfDue() async {
    if (_uid == null || _userPhone == null || _db == null) return;
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_lastCloudSyncPrefsKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (last != null && now - last < _cloudSyncInterval.inMilliseconds) return;

    try {
      await SyncService.instance.pushLocalToCloud(db: _db!, uid: _uid!, phoneNumber: _userPhone!);
      await prefs.setInt(_lastCloudSyncPrefsKey, now);
    } catch (_) {
      // transinet failure, retired next app open
    }
  }

  Future<int> _handleManualSync() async {
    if (_uid == null || _userPhone == null || _db == null) return 0;
    final count = await SyncService.instance.pushLocalToCloud(db: _db!, uid: _uid!, phoneNumber: _userPhone!);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastCloudSyncPrefsKey, DateTime.now().millisecondsSinceEpoch);
    return count;
  }

  Future<void> _handleLogout() async {
    await AuthService.instance.signOut();
    setState(() {
      _userPhone = null;
      _uid = null;
      _budgetAlerts = [];
      _showBudgetAlert = false;
      _stage = _AppStage.auth;
    });
  }

  void _setPeriod(String period) => setState(() => _period = period);

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (_stage) {
      case _AppStage.loading:
        body = const _LoadingView();
      case _AppStage.auth:
        body = AuthScreen(onSignIn: _handleSignIn, onSignUp: _handleSignUp);
      case _AppStage.onboarding:
        body = OnboardingScreen(onComplete: _handleOnboardingComplete);
      case _AppStage.main:
        body = Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              _MainTabs(
                db: _db,
                userPhone: _userPhone ?? '',
                period: _period,
                onPeriodChange: _setPeriod,
                lastSyncAt: _lastSyncAt,
                onSettingsSave: _checkAndSetBudgetAlerts,
                onSyncNow: _handleManualSync,
                onLogout: _handleLogout,
              ),
              BudgetAlertOverlay(
                alerts: _budgetAlerts,
                visible: _showBudgetAlert,
                onClose: () => setState(() => _showBudgetAlert = false),
              ),
            ],
          ),
        );
    }

    return MaterialApp(
      title: 'Finmo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, fontFamily: null),
      home: body,
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF111827),
      body: SafeArea(
        child: Center(
          child: Text('Loading...', style: TextStyle(color: Colors.white, fontSize: 18)),
        ),
      ),
    );
  }
}

class _MainTabs extends StatefulWidget {
  final Database? db;
  final String userPhone;
  final String period;
  final void Function(String) onPeriodChange;
  final int? lastSyncAt;
  final VoidCallback onSettingsSave;
  final Future<int> Function() onSyncNow;
  final VoidCallback onLogout;

  const _MainTabs({
    required this.db,
    required this.userPhone,
    required this.period,
    required this.onPeriodChange,
    required this.lastSyncAt,
    required this.onSettingsSave,
    required this.onSyncNow,
    required this.onLogout,
  });

  @override
  State<_MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<_MainTabs> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      OverviewScreen(
        db: widget.db,
        userPhone: widget.userPhone,
        period: widget.period,
        onPeriodChange: widget.onPeriodChange,
        lastSyncAt: widget.lastSyncAt,
      ),
      const SendMoneyScreen(),
      SpendingScreen(
        db: widget.db,
        userPhone: widget.userPhone,
        period: widget.period,
        onPeriodChange: widget.onPeriodChange,
        lastSyncAt: widget.lastSyncAt,
      ),
      TransactionsScreen(
        db: widget.db,
        userPhone: widget.userPhone,
        period: widget.period,
        onPeriodChange: widget.onPeriodChange,
        lastSyncAt: widget.lastSyncAt,
      ),
      SettingsScreen(
        db: widget.db,
        userPhone: widget.userPhone,
        onSave: widget.onSettingsSave,
        onSyncNow: widget.onSyncNow,
        onLogout: widget.onLogout,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFFFBBF24),
        unselectedItemColor: const Color(0xFF9CA3AF),
        selectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.send), label: 'Send'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Spending'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
