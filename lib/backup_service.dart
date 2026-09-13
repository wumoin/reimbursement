import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'models.dart';
import 'store.dart';

class BackupSummary {
  const BackupSummary({
    required this.tripCount,
    required this.expenseCount,
    required this.imageCount,
  });

  final int tripCount;
  final int expenseCount;
  final int imageCount;

  String get description =>
      '$tripCount 个批次 · $expenseCount 笔账单 · $imageCount 张图片';
}

class BackupService {
  Future<Uint8List> createBackup(AppStore store) async {
    final root = await store.rootDirectory;
    final archive = Archive();
    final data = {
      'formatVersion': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'profileName': store.profileName,
      'profileDepartment': store.profileDepartment,
      'categories': store.categories,
      'trips': store.trips.map((item) => item.toJson()).toList(),
    };
    final dataBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(data),
    );
    archive.addFile(ArchiveFile('data.json', dataBytes.length, dataBytes));

    final files = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final trip in store.trips) {
      for (final expense in trip.expenses) {
        for (final attachment in expense.attachments) {
          await _addFile(archive, root, attachment.path, files, seen);
        }
      }
      for (final payment in trip.payments) {
        final path = payment.attachmentPath;
        if (path != null) await _addFile(archive, root, path, files, seen);
      }
    }
    final exports = Directory('${root.path}${Platform.pathSeparator}exports');
    if (exports.existsSync()) {
      await for (final entity in exports.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          await _addFile(archive, root, entity.path, files, seen);
        }
      }
    }
    final manifest = {
      'formatVersion': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'dataFile': 'data.json',
      'files': files,
    };
    final manifestBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(manifest),
    );
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Future<BackupSummary> restoreBackup(AppStore store, Uint8List bytes) async {
    final decoded = ZipDecoder().decodeBytes(bytes);
    final dataFile = decoded.findFile('data.json');
    final manifestFile = decoded.findFile('manifest.json');
    if (dataFile == null || manifestFile == null) {
      throw const FormatException('备份文件缺少必要内容');
    }
    final data = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(dataFile.content as List<int>)) as Map,
    );
    if (data['formatVersion'] != 1) throw const FormatException('不支持的备份版本');
    final attachmentDir = await store.attachmentsDirectory;
    final archiveFiles = <String, String>{};
    for (final file in decoded.files) {
      if (!file.isFile || !file.name.startsWith('files/')) continue;
      final relative = file.name.substring('files/'.length);
      final target = File(
        '${attachmentDir.path}${Platform.pathSeparator}${_safeFile(relative)}',
      );
      await target.writeAsBytes(file.content as List<int>, flush: true);
      archiveFiles[relative] = target.path;
    }
    _rewritePaths(data, archiveFiles);
    store.profileName = data['profileName'] as String? ?? '';
    store.profileDepartment = data['profileDepartment'] as String? ?? '';
    final savedCategories = data['categories'] as List?;
    if (savedCategories != null && savedCategories.isNotEmpty) {
      store.categories
        ..clear()
        ..addAll(savedCategories.map((item) => item.toString()));
    }
    store.trips
      ..clear()
      ..addAll(
        (data['trips'] as List? ?? []).map(
          (item) => Trip.fromJson(Map<String, dynamic>.from(item)),
        ),
      );
    for (final trip in store.trips) {
      trip.recomputeStatus();
    }
    await store.save();
    final expenseCount = store.trips.fold(
      0,
      (sum, trip) => sum + trip.expenses.length,
    );
    final imageCount = store.trips.fold(
      0,
      (sum, trip) =>
          sum +
          trip.expenses.fold(0, (s, expense) => s + expense.attachments.length),
    );
    return BackupSummary(
      tripCount: store.trips.length,
      expenseCount: expenseCount,
      imageCount: imageCount,
    );
  }

  Future<void> _addFile(
    Archive archive,
    Directory root,
    String path,
    List<Map<String, dynamic>> files,
    Set<String> seen,
  ) async {
    final file = File(path);
    if (!await file.exists()) return;
    final relative = _relativePath(root, file.path);
    if (!seen.add(relative)) return;
    final content = await file.readAsBytes();
    final archiveName = 'files/${_safeFile(relative)}';
    archive.addFile(ArchiveFile(archiveName, content.length, content));
    files.add({
      'path': relative,
      'archivePath': archiveName,
      'size': content.length,
    });
  }

  static void _rewritePaths(dynamic value, Map<String, String> files) {
    if (value is Map) {
      for (final key in value.keys.toList()) {
        final child = value[key];
        if (child is String && (key == 'path' || key == 'attachmentPath')) {
          final relative = child.replaceAll('\\', '/').split('/').last;
          MapEntry<String, String>? match;
          for (final entry in files.entries) {
            if (entry.key.split('/').last == relative) {
              match = entry;
              break;
            }
          }
          if (match != null) value[key] = match.value;
        } else {
          _rewritePaths(child, files);
        }
      }
    } else if (value is List) {
      for (final item in value) {
        _rewritePaths(item, files);
      }
    }
  }

  static String _relativePath(Directory root, String path) {
    final normalizedRoot = root.path.replaceAll('\\', '/');
    final normalizedPath = path.replaceAll('\\', '/');
    return normalizedPath.startsWith('$normalizedRoot/')
        ? normalizedPath.substring(normalizedRoot.length + 1)
        : normalizedPath.split('/').last;
  }

  static String _safeFile(String path) =>
      path.replaceAll(RegExp(r'[^a-zA-Z0-9._/-]'), '_').replaceAll('/', '_');
}
