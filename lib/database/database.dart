import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'finmo.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: (db, version) async {
        await createTables(db);
      },
    );
  }

  Future<void> createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Users (
        Phone_Number TEXT PRIMARY KEY,
        Name TEXT,
        Firebase_Uid TEXT UNIQUE,
        Amount REAL DEFAULT 0
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Money_Transfers (
        Transfer_Id TEXT PRIMARY KEY,
        Phone_Number TEXT NOT NULL,
        Recipient_Name TEXT,
        Recipient_Phone TEXT,
        Amount REAL NOT NULL,
        Transaction_Type TEXT CHECK(Transaction_Type IN ('received','sent')) NOT NULL,
        Fee REAL DEFAULT 0,
        Date DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(Phone_Number) REFERENCES Users(Phone_Number) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Merchant_Payment (
        Transfer_Id TEXT PRIMARY KEY,
        Phone_Number TEXT NOT NULL,
        Recipient_Name TEXT,
        Recipient_Code TEXT,
        Amount REAL NOT NULL,
        Fee REAL DEFAULT 0,
        Date DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(Phone_Number) REFERENCES Users(Phone_Number) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Bundles (
        Bundle_Id TEXT PRIMARY KEY,
        Phone_Number TEXT NOT NULL,
        Bundle_Type TEXT CHECK(Bundle_Type IN ('DATA','AIRTIME')) NOT NULL,
        Bundle_Amount REAL NOT NULL,
        Amount REAL NOT NULL,
        Date DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(Phone_Number) REFERENCES Users(Phone_Number) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Bank_Transfers (
        Transfer_Id TEXT PRIMARY KEY,
        Phone_Number TEXT NOT NULL,
        Amount REAL NOT NULL,
        Transaction_Type TEXT CHECK(Transaction_Type IN ('received','sent')) NOT NULL,
        Fee REAL DEFAULT 0,
        Date DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(Phone_Number) REFERENCES Users(Phone_Number) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Others (
        Other_Id TEXT PRIMARY KEY,
        Phone_Number TEXT NOT NULL,
        Name TEXT,
        Description TEXT NOT NULL,
        Amount REAL NOT NULL,
        Date DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(Phone_Number) REFERENCES Users(Phone_Number) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Settings (
        Settings_Id TEXT PRIMARY KEY,
        Phone_Number TEXT NOT NULL UNIQUE,
        Theme TEXT CHECK(Theme IN ('Light','Dark')) DEFAULT 'Light',
        General_Spending_Limit REAL DEFAULT 0,
        Money_Transfer_Limit REAL DEFAULT 0,
        Bundles_Limit REAL DEFAULT 0,
        Merchant_Limit REAL DEFAULT 0,
        Bank_Transfer_Limit REAL DEFAULT 0,
        Utilities_Limit REAL DEFAULT 0,
        Agent_Limit REAL DEFAULT 0,
        Others_Limit REAL DEFAULT 0,
        FOREIGN KEY(Phone_Number) REFERENCES Users(Phone_Number) ON DELETE CASCADE
      );
    ''');

    
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Agent_Transactions (
        Transaction_Id TEXT PRIMARY KEY,
        Phone_Number TEXT NOT NULL,
        Agent_Name TEXT NOT NULL,
        Amount REAL NOT NULL,
        Fee REAL DEFAULT 0,
        Date DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(Phone_Number) REFERENCES Users(Phone_Number) ON DELETE CASCADE
      );
    ''');


    await db.execute('''
      CREATE TABLE IF NOT EXISTS Utilities (
        Transaction_Id TEXT PRIMARY KEY,
        Phone_Number TEXT NOT NULL,
        Name TEXT NOT NULL,
        Amount REAL NOT NULL,
        Fee REAL DEFAULT 0,
        Date DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(Phone_Number) REFERENCES Users(Phone_Number) ON DELETE CASCADE
      );
    ''');
  }
  static const Map<String, String> transactionTables = {
    'Money_Transfers': 'Transfer_Id',
    'Merchant_Payment': 'Transfer_Id',
    'Bundles': 'Bundle_Id',
    'Bank_Transfers': 'Transfer_Id',
    'Others': 'Other_Id',
    'Agent_Transactions': 'Transaction_Id',
    'Utilities': 'Transaction_Id',
  };
}
