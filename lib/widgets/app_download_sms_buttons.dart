import 'package:flutter/material.dart';

import '../core/services/app_download_sms_service.dart';
import '../core/theme/app_theme.dart';

/// «Send Apple» / «Send Google» app-download SMS buttons.
class AppDownloadSmsButtons extends StatefulWidget {
  const AppDownloadSmsButtons({
    super.key,
    required this.phone,
    this.displayName,
    this.username,
    this.password = '000000',
    this.refType,
    this.refId,
    this.userId,
    this.companyId,
    this.dense = false,
    this.enabled = true,
    this.onSent,
  });

  final String? phone;
  final String? displayName;
  final String? username;
  final String? password;
  final String? refType;
  final String? refId;
  final String? userId;
  final String? companyId;
  final bool dense;
  final bool enabled;
  final void Function(AppDownloadSmsResult result)? onSent;

  @override
  State<AppDownloadSmsButtons> createState() => _AppDownloadSmsButtonsState();
}

class _AppDownloadSmsButtonsState extends State<AppDownloadSmsButtons> {
  bool _busy = false;
  int? _remaining;

  bool get _hasPhone {
    final p = widget.phone?.replaceAll(RegExp(r'\D'), '') ?? '';
    return p.length >= 8;
  }

  @override
  void initState() {
    super.initState();
    _loadRemaining();
  }

  Future<void> _loadRemaining() async {
    try {
      final n = await AppDownloadSmsService.remainingCodes();
      if (mounted) setState(() => _remaining = n);
    } catch (_) {
      /* ignore — buttons still work; server will reject if empty */
    }
  }

  Future<void> _send(String platform) async {
    final phone = widget.phone?.trim() ?? '';
    if (!_hasPhone) {
      _toast('Mangler gyldig telefonnummer', error: true);
      return;
    }

    final isApple = platform == 'apple';
    final label = isApple ? 'Apple (engangskode)' : 'Google Play';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Send $label?'),
        content: Text(
          isApple
              ? 'Sender app-lenke med unik Apple-kode til $phone'
                  '${widget.displayName != null ? ' (${widget.displayName})' : ''}.\n\n'
                  'Koden fjernes fra listen og kan ikke brukes på nytt.'
                  '${_remaining != null ? '\n\nLedige koder: $_remaining' : ''}'
              : 'Sender Google Play-lenke til $phone'
                  '${widget.displayName != null ? ' (${widget.displayName})' : ''}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send SMS'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await AppDownloadSmsService.send(
        platform: platform,
        phone: phone,
        displayName: widget.displayName,
        username: widget.username,
        password: widget.password,
        refType: widget.refType,
        refId: widget.refId,
        userId: widget.userId,
        companyId: widget.companyId,
      );
      if (!mounted) return;
      setState(() {
        _remaining = result.remainingCodes ?? _remaining;
        _busy = false;
      });
      _toast(
        isApple
            ? 'Apple-SMS sendt'
                '${result.remainingCodes != null ? ' · ${result.remainingCodes} koder igjen' : ''}'
            : 'Google Play-SMS sendt',
      );
      widget.onSent?.call(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      _toast(msg, error: true);
      await _loadRemaining();
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSend = widget.enabled && !_busy && _hasPhone;
    final appleDisabled = !canSend || (_remaining != null && _remaining! <= 0);

    final appleBtn = OutlinedButton.icon(
      onPressed: appleDisabled ? null : () => _send('apple'),
      icon: Icon(Icons.apple, size: widget.dense ? 16 : 18),
      label: Text(widget.dense ? 'Apple' : 'Send Apple'),
    );
    final googleBtn = OutlinedButton.icon(
      onPressed: canSend ? () => _send('google') : null,
      icon: Icon(Icons.android, size: widget.dense ? 16 : 18),
      label: Text(widget.dense ? 'Google' : 'Send Google'),
      style: OutlinedButton.styleFrom(
        foregroundColor: DriftProTheme.primaryGreen,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            appleBtn,
            googleBtn,
            if (_busy)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        if (_remaining != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Apple-koder igjen: $_remaining',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
        if (!_hasPhone)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Legg inn telefonnummer for å sende app-lenke',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
            ),
          ),
      ],
    );
  }
}
