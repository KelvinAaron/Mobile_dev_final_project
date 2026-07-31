import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'components/budget_alert_overlay.dart';
import 'database/database.dart';
import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/email_verification_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/overview_screen.dart';
import 'screens/send_money_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/spending_screen.dart';
import 'screens/transactions_screen.dart';
import 'services/auth_service.dart';
import 'services/sms_service.dart';
import 'services/sync_service.dart';
import 'state/app_state.dart';
import 'styles/app_theme.dart';
import 'utils/budget_utils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final appState = AppState();
  await appState.load();
  runApp(ChangeNotifierProvider.value(value: appState, child: const FinmoApp()));
}

enum _AppStage { loading, auth, emailVerification, onboarding, main }

const _lastSmsSyncPrefsKey = 'finmo_last_sms_sync';
const _lastCloudSyncPrefsKey = 'finmo_last_cloud_sync';
const _smsDateRepairPrefsKey = 'finmo_sms_date_repair_v1';
const _balanceRepairPrefsKey = 'finmo_balance_parser_v3';
const _cloudSyncInterval = Duration(hours: 24);

String _smsSyncKeyFor(String uid) => '${_lastSmsSyncPrefsKey}_$uid';
String _cloudSyncKeyFor(String uid) => '${_lastCloudSyncPrefsKey}_$uid';

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
  List<BudgetAlert> _budgetAlerts = [];
  bool _showBudgetAlert = false;
  int? _lastSyncAt;
  int _dataRevision = 0;
  bool _isSyncingSms = false;
  String? _startupError;

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
    try {
      final db = await AppDatabase.instance.database;
      if (!mounted) return;
      setState(() => _db = db);

      final firebaseUser = AuthService.instance.currentUser;
      if (firebaseUser == null) {
        setState(() => _stage = _AppStage.auth);
        return;
      }
      if (AuthService.instance.requiresEmailVerification) {
        setState(() => _stage = _AppStage.emailVerification);
        return;
      }
      await _postAuthInit(firebaseUser.uid);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _startupError =
            'Finmo could not restore your account. Check your connection and '
            'Firestore rules, then sign in again.';
        _stage = _AppStage.auth;
      });
    }
  }

  // Resolves the local user row for [uid] if this is a new device or a fresh sign-in after logout
  Future<void> _postAuthInit(String uid) async {
    final db = _db!;
    final localUserRows = await db.query('Users', where: 'Firebase_Uid = ?', whereArgs: [uid], limit: 1);

    String? phoneNumber;
    if (localUserRows.isEmpty) {
      phoneNumber = await SyncService.instance
          .pullCloudToLocal(db: db, uid: uid)
          .timeout(const Duration(seconds: 15));
    } else {
      phoneNumber = localUserRows.first['Phone_Number'] as String?;
    }

    if (phoneNumber == null) {
      setState(() => _stage = _AppStage.auth);
      return;
    }

    _userPhone = phoneNumber;
    _uid = uid;
    final prefs = await SharedPreferences.getInstance();
    _lastSyncAt = prefs.getInt(_smsSyncKeyFor(uid));
    try {
      await SyncService.instance.pushProfileToCloud(
        db: db,
        uid: uid,
        phoneNumber: phoneNumber,
      );
    } catch (_) {
      // Local access remains available offline. Automatic/manual sync retries
      // creation of a missing Firestore profile.
    }

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
    final db = _db!;
    final normalizedPhone = SyncService.normalizePhoneNumber(phone);
    final credential = await AuthService.instance.signUp(email: email, password: password);
    final uid = credential.user!.uid;

    final localUsers = await db.query('Users', columns: ['Phone_Number']);
    for (final row in localUsers) {
      final storedPhone = row['Phone_Number'] as String? ?? '';
      if (SyncService.normalizePhoneNumber(storedPhone) == normalizedPhone) {
        // Replace a stale local profile that uses an equivalent phone format.
        await db.delete('Users', where: 'Phone_Number = ?', whereArgs: [storedPhone]);
      }
    }
    await db.insert('Users', {'Phone_Number': phone, 'Name': '', 'Firebase_Uid': uid, 'Amount': 0});
    _userPhone = phone;
    _uid = uid;
    setState(() => _stage = _AppStage.emailVerification);
    try {
      await AuthService.instance.sendEmailVerification();
    } catch (_) {
      // The account remains on the verification screen, where the user can
      // retry with the resend action when connectivity is restored.
    }
  }

  Future<void> _handleSignIn(String email, String password) async {
    final credential = await AuthService.instance.signIn(email: email, password: password);
    if (AuthService.instance.requiresEmailVerification) {
      setState(() => _stage = _AppStage.emailVerification);
      return;
    }
    await _postAuthInit(credential.user!.uid);
    if (_userPhone == null) {
      throw Exception('No account data found for this login. Please sign up.');
    }
  }

  Future<bool> _handleGoogleSignIn() async {
    final credential = await AuthService.instance.signInWithGoogle();
    await _postAuthInit(credential.user!.uid);
    return _userPhone == null;
  }

  Future<void> _createGoogleProfile(String phone) async {
    final user = AuthService.instance.currentUser;
    if (user == null) throw Exception('Google sign-in was cancelled.');
    final uid = user.uid;
    final db = _db!;
    final normalizedPhone = SyncService.normalizePhoneNumber(phone);
    final localUsers = await db.query('Users', columns: ['Phone_Number']);
    for (final row in localUsers) {
      final storedPhone = row['Phone_Number'] as String? ?? '';
      if (SyncService.normalizePhoneNumber(storedPhone) == normalizedPhone) {
        await db.delete('Users', where: 'Phone_Number = ?', whereArgs: [storedPhone]);
      }
    }
    await db.insert('Users', {
      'Phone_Number': phone,
      'Name': user.displayName ?? '',
      'Firebase_Uid': uid,
      'Amount': 0,
    });
    _userPhone = phone;
    _uid = uid;
    await SyncService.instance.pushLocalToCloud(
      db: db,
      uid: uid,
      phoneNumber: phone,
    );
    setState(() => _stage = _AppStage.onboarding);
  }

  Future<bool> _checkEmailVerification() async {
    final verified = await AuthService.instance.reloadAndCheckEmailVerified();
    if (!verified) return false;
    final user = AuthService.instance.currentUser;
    if (user == null) return false;
    if (_db != null && _userPhone != null) {
      await SyncService.instance.pushProfileToCloud(
        db: _db!,
        uid: user.uid,
        phoneNumber: _userPhone!,
      );
    }
    await _postAuthInit(user.uid);
    return true;
  }

  Future<void> _resendEmailVerification() {
    return AuthService.instance.sendEmailVerification();
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
      var permissionWasJustGranted = false;
      if (Platform.isAndroid) {
        final previousStatus = await Permission.sms.status;
        if (!previousStatus.isGranted) {
          final requestedStatus = await Permission.sms.request();
          if (!requestedStatus.isGranted) {
            if (requestedStatus.isPermanentlyDenied && mounted) {
              final openSettings = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('SMS permission required'),
                  content: const Text(
                    'Finmo needs SMS access to read Mobile Money balances and transactions. '
                    'Enable SMS permission in Android settings.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Not now'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Open settings'),
                    ),
                  ],
                ),
              );
              if (openSettings == true) await openAppSettings();
            }
            return;
          }
          permissionWasJustGranted = true;
        }
      }

      final userRows = await _db!.query(
        'Users',
        columns: ['Amount'],
        where: 'Phone_Number = ?',
        whereArgs: [_userPhone],
        limit: 1,
      );
      final storedBalance = userRows.isEmpty
          ? 0
          : (userRows.first['Amount'] as num?)?.toDouble() ?? 0;
      final needsBalanceBootstrap = storedBalance == 0;
      final prefs = await SharedPreferences.getInstance();
      final needsDateRepair = !(prefs.getBool(_smsDateRepairPrefsKey) ?? false);
      final needsBalanceRepair =
          !(prefs.getBool(_balanceRepairPrefsKey) ?? false);
      final useIncremental =
          incremental &&
          !permissionWasJustGranted &&
          !needsBalanceBootstrap &&
          !needsDateRepair &&
          !needsBalanceRepair;
      final minDate = useIncremental && _lastSyncAt != null ? _lastSyncAt! + 1 : 0;
      final result = await SmsService.instance.readMMoneyMessages(
        db: _db!,
        userPhone: _userPhone!,
        minDate: minDate,
      );
      if (result != null) {
        final uid = _uid;
        if (uid != null) {
          await prefs.setInt(_smsSyncKeyFor(uid), result.maxMsgDate);
        }
        await prefs.setBool(_smsDateRepairPrefsKey, true);
        await prefs.setBool(_balanceRepairPrefsKey, true);
        if (mounted) {
          setState(() {
            _lastSyncAt = result.maxMsgDate;
            _dataRevision++;
          });
        } else {
          _lastSyncAt = result.maxMsgDate;
        }
      }
      await _checkAndSetBudgetAlerts();
    } finally {
      _isSyncingSms = false;
    }
  }

  Future<void> _triggerCloudSyncIfDue() async {
    if (_uid == null || _userPhone == null || _db == null) return;
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_cloudSyncKeyFor(_uid!));
    final now = DateTime.now().millisecondsSinceEpoch;
    if (last != null && now - last < _cloudSyncInterval.inMilliseconds) return;

    try {
      await SyncService.instance.pushLocalToCloud(db: _db!, uid: _uid!, phoneNumber: _userPhone!);
      await prefs.setInt(_cloudSyncKeyFor(_uid!), now);
    } catch (_) {
      // transinet failure, retired next app open
    }
  }

  Future<int> _handleManualSync() async {
    if (_uid == null || _userPhone == null || _db == null) return 0;
    await _syncSmsFull();
    final count = await SyncService.instance.pushLocalToCloud(db: _db!, uid: _uid!, phoneNumber: _userPhone!);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _cloudSyncKeyFor(_uid!),
      DateTime.now().millisecondsSinceEpoch,
    );
    return count;
  }

  Future<void> _handleLogout() async {
    await AuthService.instance.signOut();
    setState(() {
      _userPhone = null;
      _uid = null;
      _budgetAlerts = [];
      _showBudgetAlert = false;
      _lastSyncAt = null;
      _dataRevision = 0;
      _stage = _AppStage.auth;
    });
  }

  Future<bool> _handleDeleteTransaction(String table, String id) async {
    if (_db == null || _uid == null || _userPhone == null) {
      throw StateError('You must be signed in to delete a transaction.');
    }
    final cloudDeleted = await SyncService.instance.deleteTransaction(
      db: _db!,
      uid: _uid!,
      phoneNumber: _userPhone!,
      table: table,
      id: id,
    );
    await _checkAndSetBudgetAlerts();
    setState(() => _dataRevision++);
    return cloudDeleted;
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (_stage) {
      case _AppStage.loading:
        body = const _LoadingView();
      case _AppStage.auth:
        body = AuthScreen(
          onSignIn: _handleSignIn,
          onSignUp: _handleSignUp,
          onGoogleSignIn: _handleGoogleSignIn,
          onCreateGoogleProfile: _createGoogleProfile,
          initialError: _startupError,
        );
      case _AppStage.emailVerification:
        body = EmailVerificationScreen(
          email: AuthService.instance.currentUser?.email ?? 'your email address',
          onCheckVerification: _checkEmailVerification,
          onResend: _resendEmailVerification,
          onLogout: _handleLogout,
        );
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
                period: context.watch<AppState>().period,
                onPeriodChange: context.read<AppState>().setPeriod,
                lastSyncAt: _dataRevision,
                onSettingsSave: _checkAndSetBudgetAlerts,
                onSyncNow: _handleManualSync,
                onLogout: _handleLogout,
                onDeleteTransaction: _handleDeleteTransaction,
                isLightMode: context.watch<AppState>().isLightMode,
                onLightModeChanged: context.read<AppState>().setLightMode,
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
      themeMode: context.watch<AppState>().isLightMode ? ThemeMode.light : ThemeMode.dark,
      theme: FinmoTheme.light,
      darkTheme: FinmoTheme.dark,
      home: body,
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Text(
            'Loading...',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18),
          ),
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
  final Future<bool> Function(String table, String id) onDeleteTransaction;
  final bool isLightMode;
  final ValueChanged<bool> onLightModeChanged;

  const _MainTabs({
    required this.db,
    required this.userPhone,
    required this.period,
    required this.onPeriodChange,
    required this.lastSyncAt,
    required this.onSettingsSave,
    required this.onSyncNow,
    required this.onLogout,
    required this.onDeleteTransaction,
    required this.isLightMode,
    required this.onLightModeChanged,
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
        onDelete: widget.onDeleteTransaction,
      ),
      SettingsScreen(
        db: widget.db,
        userPhone: widget.userPhone,
        onSave: widget.onSettingsSave,
        onSyncNow: widget.onSyncNow,
        onLogout: widget.onLogout,
        isLightMode: widget.isLightMode,
        onLightModeChanged: widget.onLightModeChanged,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Theme.of(context).colorScheme.surface,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
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
