import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme.dart';
import '../../../shared/audio_feedback.dart';
import '../../../shared/cache.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../archive/presentation/archive_providers.dart';
import '../../clients/presentation/clients_providers.dart';
import '../../companies/presentation/companies_providers.dart';
import '../../countries/presentation/countries_providers.dart';
import '../../currency_buy/presentation/currency_buys_providers.dart';
import '../../exchange_companies/presentation/exchange_companies_providers.dart';
import '../../transfers/presentation/beneficiaries_providers.dart';
import '../../transfers/presentation/transfers_providers.dart';
import '../data/backup_repository.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
            error ? AppColors.negative.withValues(alpha: 0.85) : null,
        content: Text(text),
      ),
    );
  }

  Future<void> _run(Future<void> Function() action, String logTag) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e, st) {
      AppLogger.error(logTag, e, st);
      _snack(friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fileName(DateTime t) =>
      'eshary-backup-${DateFormat('yyyyMMdd-HHmm').format(t)}.json';

  Future<void> _saveFile(Map<String, dynamic> backup, DateTime t) async {
    final bytes = utf8.encode(jsonEncode(backup));
    await Share.shareXFiles([
      XFile.fromData(
        bytes,
        name: _fileName(t),
        mimeType: 'application/json',
      ),
    ]);
  }

  Future<void> _backupNow() => _run(() async {
        await ref.read(backupRepositoryProvider).backupNow();
        ref.invalidate(backupsListProvider);
        _snack('تم إنشاء نسخة احتياطية');
      }, 'backup.now');

  Future<void> _downloadCurrent() => _run(() async {
        final data = await ref.read(backupRepositoryProvider).export();
        await _saveFile(data, DateTime.now());
      }, 'backup.downloadCurrent');

  Future<void> _download(BackupInfo b) => _run(() async {
        final data = await ref.read(backupRepositoryProvider).get(b.id);
        await _saveFile(data, b.createdAt.toLocal());
      }, 'backup.download');

  Future<void> _restoreFromStored(BackupInfo b) async {
    final ok = await _confirmRestore(
      'نسخة ${DateFormat('yyyy/MM/dd HH:mm').format(b.createdAt.toLocal())}',
    );
    if (ok != true) return;
    await _run(() async {
      final data = await ref.read(backupRepositoryProvider).get(b.id);
      await _applyRestore(data);
    }, 'backup.restoreStored');
  }

  Future<void> _uploadAndRestore() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final bytes = picked?.files.single.bytes;
    if (bytes == null) return;

    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      _snack('الملف غير صالح', error: true);
      return;
    }
    if (data['app'] != 'eshary' || data['tables'] is! Map) {
      _snack('هذا الملف ليس نسخة احتياطية من التطبيق', error: true);
      return;
    }

    final ok = await _confirmRestore(picked!.files.single.name);
    if (ok != true) return;
    await _run(() => _applyRestore(data), 'backup.restoreUpload');
  }

  Future<void> _applyRestore(Map<String, dynamic> data) async {
    await ref.read(backupRepositoryProvider).restore(data);
    await ref.read(jsonCacheProvider).clear();
    _refreshAppData();
    ref.invalidate(backupsListProvider);
    playAlert();
    _snack('تمت الاستعادة بنجاح');
  }

  void _refreshAppData() {
    ref.invalidate(companiesListProvider);
    ref.invalidate(allExchangesProvider);
    ref.invalidate(exchangeCompaniesListProvider);
    ref.invalidate(countriesListProvider);
    ref.invalidate(clientsListProvider);
    ref.invalidate(beneficiariesListProvider);
    ref.invalidate(dailyTransfersProvider);
    ref.invalidate(todayTransfersProvider);
    ref.invalidate(todayBuysProvider);
    ref.invalidate(archivedTransfersProvider);
    ref.invalidate(dailyBuysProvider);
    ref.invalidate(pendingBuysProvider);
    ref.invalidate(archivedBuysProvider);
    ref.invalidate(archivedSoldTotalProvider);
    ref.invalidate(archivedBoughtTotalProvider);
  }

  /// Double confirmation: restore replaces all operational data.
  Future<bool?> _confirmRestore(String source) async {
    final first = await _confirm(
      title: 'استعادة نسخة احتياطية؟',
      body: 'المصدر: $source\n\n'
          'سيتم استبدال جميع الشركات والعملاء والحوالات والمشتريات والموظفين '
          'والفروع الحالية بما في هذه النسخة. الحسابات والتراخيص لا تتأثر. '
          'تُحفظ نسخة أمان تلقائياً قبل الاستعادة.',
      confirmLabel: 'متابعة',
    );
    if (first != true || !mounted) return false;
    return _confirm(
      title: 'تأكيد نهائي',
      body: 'هل أنت متأكد من الاستبدال الكامل؟',
      confirmLabel: 'استعادة الآن',
      destructive: true,
    );
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    bool destructive = false,
  }) {
    return showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHigh,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textLow,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: destructive
                          ? FilledButton.styleFrom(
                              backgroundColor: AppColors.negative,
                            )
                          : null,
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: Text(confirmLabel),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _kindLabel(String kind) => switch (kind) {
        'auto' => 'تلقائية',
        'manual' => 'يدوية',
        'pre_restore' => 'قبل استعادة',
        _ => kind,
      };

  String _size(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).toStringAsFixed(0)} KB';

  @override
  Widget build(BuildContext context) {
    final backups = ref.watch(backupsListProvider);
    final df = DateFormat('yyyy/MM/dd  HH:mm');

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('النسخ الاحتياطي')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'يُنشأ نسخ احتياطي تلقائي كل ساعة ويُحتفظ بآخر 7 أيام.',
              style: TextStyle(color: AppColors.textLow, fontSize: 12),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _downloadCurrent,
              icon: const FaIcon(FontAwesomeIcons.download, size: 14),
              label: const Text('تنزيل نسخة احتياطية الآن'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _backupNow,
              icon: const FaIcon(FontAwesomeIcons.floppyDisk, size: 14),
              label: const Text('إنشاء نسخة داخل النظام'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _uploadAndRestore,
              icon: const FaIcon(FontAwesomeIcons.upload, size: 14),
              label: const Text('رفع نسخة احتياطية واستعادتها'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.warning,
                side: BorderSide(
                  color: AppColors.warning.withValues(alpha: 0.5),
                ),
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 24),
            const Text(
              'النسخ المحفوظة',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textHigh,
              ),
            ),
            const SizedBox(height: 8),
            backups.when(
              skipLoadingOnReload: true,
              skipError: true,
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (e, _) => Text(friendlyError(e)),
              data: (rows) {
                if (rows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'لا توجد نسخ محفوظة بعد',
                      style: TextStyle(color: AppColors.textLow),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final b in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    df.format(b.createdAt.toLocal()),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textHigh,
                                    ),
                                  ),
                                  Text(
                                    '${_kindLabel(b.kind)} · ${_size(b.sizeBytes)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textLow,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'تنزيل',
                              onPressed: _busy ? null : () => _download(b),
                              icon: const FaIcon(
                                FontAwesomeIcons.download,
                                size: 15,
                              ),
                            ),
                            IconButton(
                              tooltip: 'استعادة',
                              onPressed:
                                  _busy ? null : () => _restoreFromStored(b),
                              icon: const FaIcon(
                                FontAwesomeIcons.clockRotateLeft,
                                size: 15,
                                color: AppColors.warning,
                              ),
                            ),
                          ]),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
