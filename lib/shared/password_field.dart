import 'package:flutter/material.dart';

import '../core/theme.dart';

/// A password field with an eye on the left (the end side in a right-to-left
/// screen) that shows or hides what was typed, letters and digits alike, so
/// the user can check it before pressing the button. Hidden by default.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'كلمة المرور',
  });

  final TextEditingController controller;
  final String label;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: !_show,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textLow),
        suffixIcon: IconButton(
          key: const ValueKey('password-eye'),
          tooltip: _show ? 'إخفاء' : 'إظهار',
          icon: Icon(
            _show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: _show ? AppColors.accent : AppColors.textLow,
          ),
          onPressed: () => setState(() => _show = !_show),
        ),
      ),
    );
  }
}
