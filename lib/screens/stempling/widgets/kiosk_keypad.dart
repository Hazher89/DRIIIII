import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class KioskKeypad extends StatelessWidget {
  const KioskKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    required this.onOk,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onOk;

  static const _gap = 8.0;
  static const _columns = 4;
  static const _rows = 4;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight.isFinite ? constraints.maxHeight : maxW;

        final keyFromWidth = (maxW - _gap * (_columns - 1)) / _columns;
        final keyFromHeight = (maxH - _gap * (_rows - 1)) / _rows;
        final keySize = keyFromWidth < keyFromHeight ? keyFromWidth : keyFromHeight;

        final padWidth = _columns * keySize + _gap * (_columns - 1);
        final padHeight = _rows * keySize + _gap * (_rows - 1);

        return SizedBox(
          width: padWidth,
          height: padHeight,
          child: Column(
            children: [
              _row(keySize, ['7', '8', '9'], backspace: true),
              SizedBox(height: _gap),
              _row(keySize, ['4', '5', '6']),
              SizedBox(height: _gap),
              _row(keySize, ['1', '2', '3']),
              SizedBox(height: _gap),
              _bottomRow(keySize),
            ],
          ),
        );
      },
    );
  }

  Widget _row(double size, List<String> digits, {bool backspace = false}) {
    return SizedBox(
      height: size,
      child: Row(
        children: [
          for (var i = 0; i < digits.length; i++) ...[
            if (i > 0) const SizedBox(width: _gap),
            Expanded(child: _digitKey(size, digits[i])),
          ],
          if (backspace) ...[
            const SizedBox(width: _gap),
            Expanded(
              child: _actionKey(
                size: size,
                icon: Icons.backspace_outlined,
                onTap: onBackspace,
              ),
            ),
          ] else ...[
            const SizedBox(width: _gap),
            const Expanded(child: SizedBox()),
          ],
        ],
      ),
    );
  }

  Widget _bottomRow(double size) {
    return SizedBox(
      height: size,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: _digitKey(size, '0'),
          ),
          const SizedBox(width: _gap),
          Expanded(
            child: _actionKey(
              size: size,
              label: 'OK',
              color: const Color(0xFF1565C0),
              onTap: onOk,
            ),
          ),
          const SizedBox(width: _gap),
          const Expanded(child: SizedBox()),
        ],
      ),
    );
  }

  Widget _digitKey(double size, String digit) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          HapticFeedback.lightImpact();
          onDigit(digit);
        },
        child: SizedBox(
          height: size,
          child: Center(
            child: Text(
              digit,
              style: TextStyle(
                fontSize: size * 0.35,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionKey({
    required double size,
    String? label,
    IconData? icon,
    Color? color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color ?? Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: SizedBox(
          height: size,
          child: Center(
            child: icon != null
                ? Icon(icon, color: Colors.black54, size: size * 0.3)
                : Text(
                    label ?? '',
                    style: TextStyle(
                      fontSize: size * 0.22,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
