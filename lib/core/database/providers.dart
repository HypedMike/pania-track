import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'database.dart';

/// Opens the database lazily; tests override it with an in-memory one.
final databaseProvider = Provider<Future<Database> Function()>((ref) => getDatabase);
