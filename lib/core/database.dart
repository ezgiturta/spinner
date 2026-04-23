import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AppDatabase {
  static Database? _db;

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final path = join(await getDatabasesPath(), 'spinner.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE records (
            id TEXT PRIMARY KEY,
            discogs_id INTEGER UNIQUE,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            year INTEGER,
            label TEXT,
            catalog_no TEXT,
            format TEXT,
            pressing_country TEXT,
            pressing_plant TEXT,
            matrix TEXT,
            mastering_engineer TEXT,
            vinyl_color TEXT,
            is_signed INTEGER DEFAULT 0,
            is_numbered INTEGER DEFAULT 0,
            edition_notes TEXT,
            cover_url TEXT,
            cover_local_path TEXT,
            condition TEXT,
            median_value REAL,
            low_value REAL,
            high_value REAL,
            price_history TEXT,
            value_updated_at TEXT,
            alert_price REAL,
            in_collection INTEGER DEFAULT 0,
            in_wantlist INTEGER DEFAULT 0,
            folder_id INTEGER,
            synced_at TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE spins (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            record_id TEXT NOT NULL,
            spun_at TEXT NOT NULL,
            notes TEXT,
            FOREIGN KEY (record_id) REFERENCES records(id)
          )
        ''');

        await db.execute('''
          CREATE TABLE cleans (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            record_id TEXT NOT NULL,
            cleaned_at TEXT NOT NULL,
            method TEXT,
            FOREIGN KEY (record_id) REFERENCES records(id)
          )
        ''');

        await db.execute(
            'CREATE INDEX idx_records_discogs ON records(discogs_id)');
        await db.execute(
            'CREATE INDEX idx_spins_record ON spins(record_id)');
        await db.execute(
            'CREATE INDEX idx_cleans_record ON cleans(record_id)');
      },
    );
  }

  // ── Records ──

  static Future<int> insertRecord(Map<String, dynamic> record) async {
    final db = await instance;
    return db.insert('records', record,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<int> updateRecord(
      String id, Map<String, dynamic> values) async {
    final db = await instance;
    return db.update('records', values, where: 'id = ?', whereArgs: [id]);
  }

  static Future<Map<String, dynamic>?> getRecordById(String id) async {
    final db = await instance;
    final rows = await db.query('records', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  static Future<Map<String, dynamic>?> getRecordByDiscogsId(
      int discogsId) async {
    final db = await instance;
    final rows = await db
        .query('records', where: 'discogs_id = ?', whereArgs: [discogsId]);
    return rows.isEmpty ? null : rows.first;
  }

  static Future<List<Map<String, dynamic>>> getCollection({
    String? search,
    String? sortBy,
    bool ascending = true,
  }) async {
    final db = await instance;
    String where = 'in_collection = 1';
    List<dynamic> args = [];
    if (search != null && search.isNotEmpty) {
      where += ' AND (title LIKE ? OR artist LIKE ?)';
      args.addAll(['%$search%', '%$search%']);
    }
    final order = sortBy != null
        ? '$sortBy ${ascending ? "ASC" : "DESC"}'
        : 'artist ASC';
    return db.query('records', where: where, whereArgs: args, orderBy: order);
  }

  static Future<List<Map<String, dynamic>>> getWantlist() async {
    final db = await instance;
    return db.query('records',
        where: 'in_wantlist = 1', orderBy: 'artist ASC');
  }

  static Future<int> getCollectionCount() async {
    final db = await instance;
    final result =
        await db.rawQuery('SELECT COUNT(*) as c FROM records WHERE in_collection = 1');
    return result.first['c'] as int;
  }

  static Future<double> getCollectionValue() async {
    final db = await instance;
    final result = await db.rawQuery(
        'SELECT SUM(median_value) as v FROM records WHERE in_collection = 1');
    return (result.first['v'] as num?)?.toDouble() ?? 0.0;
  }

  // ── Spins ──

  static Future<void> logSpin(String recordId, {String? notes}) async {
    final db = await instance;
    await db.insert('spins', {
      'record_id': recordId,
      'spun_at': DateTime.now().toIso8601String(),
      'notes': notes,
    });
  }

  static Future<List<Map<String, dynamic>>> getSpins(String recordId) async {
    final db = await instance;
    return db.query('spins',
        where: 'record_id = ?',
        whereArgs: [recordId],
        orderBy: 'spun_at DESC');
  }

  static Future<int> getSpinCount(String recordId) async {
    final db = await instance;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as c FROM spins WHERE record_id = ?', [recordId]);
    return result.first['c'] as int;
  }

  static Future<int> getTotalSpins() async {
    final db = await instance;
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM spins');
    return result.first['c'] as int;
  }

  // ── Cleans ──

  static Future<void> logClean(String recordId, {String? method}) async {
    final db = await instance;
    await db.insert('cleans', {
      'record_id': recordId,
      'cleaned_at': DateTime.now().toIso8601String(),
      'method': method,
    });
  }

  static Future<List<Map<String, dynamic>>> getCleans(String recordId) async {
    final db = await instance;
    return db.query('cleans',
        where: 'record_id = ?',
        whereArgs: [recordId],
        orderBy: 'cleaned_at DESC');
  }

  static Future<String?> getLastClean(String recordId) async {
    final db = await instance;
    final rows = await db.query('cleans',
        where: 'record_id = ?',
        whereArgs: [recordId],
        orderBy: 'cleaned_at DESC',
        limit: 1);
    return rows.isEmpty ? null : rows.first['cleaned_at'] as String;
  }

  // ── Recently scanned ──

  static Future<List<Map<String, dynamic>>> getRecentlyScanned(
      {int limit = 10}) async {
    final db = await instance;
    return db.query('records',
        orderBy: 'synced_at DESC', limit: limit);
  }

  // ── Neglected records ──

  static Future<List<Map<String, dynamic>>> getNeglectedRecords(
      {int months = 6, int limit = 5}) async {
    final db = await instance;
    final cutoff =
        DateTime.now().subtract(Duration(days: months * 30)).toIso8601String();
    return db.rawQuery('''
      SELECT r.* FROM records r
      LEFT JOIN (
        SELECT record_id, MAX(spun_at) as last_spun
        FROM spins GROUP BY record_id
      ) s ON r.id = s.record_id
      WHERE r.in_collection = 1
      AND (s.last_spun IS NULL OR s.last_spun < ?)
      ORDER BY s.last_spun ASC
      LIMIT ?
    ''', [cutoff, limit]);
  }
}
