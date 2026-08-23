import 'package:flutter/material.dart';

import '../../../ui/core/design_system/design_system.dart';

/// Shared auth back button. Delegates to the global Chaty navigation primitive
/// so auth screens keep the same hit target and chevron geometry as the app.
class AuthBackButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const AuthBackButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ChatyBackButton(onPressed: onPressed),
    );
  }
}

class AuthTextField extends StatelessWidget {
  final String label;
  final String hintText;
  final TextEditingController? controller;
  final bool obscureText;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ThemeConfig theme;

  const AuthTextField({
    super.key,
    required this.label,
    required this.hintText,
    required this.theme,
    this.controller,
    this.obscureText = false,
    this.suffixIcon,
    this.prefixIcon,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.validator,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: theme.primaryTextColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          validator: validator,
          onChanged: onChanged,
          autofillHints: _autofillHints,
          style: TextStyle(
            color: theme.primaryTextColor,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              color: theme.secondaryTextColor.withValues(alpha: 0.5),
              fontSize: 14,
            ),
            filled: true,
            fillColor: context.colors.inputFill,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 16,
            ),
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            border: _border(context.colors.border, 1),
            enabledBorder: _border(context.colors.border, 1),
            focusedBorder: _border(theme.accentColor, 1.8),
            errorBorder: _border(theme.dangerColor, 1.2),
            focusedErrorBorder: _border(theme.dangerColor, 1.8),
          ),
        ),
      ],
    );
  }

  List<String>? get _autofillHints {
    if (obscureText) return const <String>[AutofillHints.password];
    if (keyboardType == TextInputType.emailAddress) {
      return const <String>[AutofillHints.email];
    }
    return null;
  }

  OutlineInputBorder _border(Color color, double width) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: color, width: width),
  );
}

class AuthPrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final ThemeConfig theme;

  const AuthPrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    required this.theme,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: text,
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.accentColor,
            foregroundColor: theme.onAccentColor,
            disabledBackgroundColor: theme.accentColor.withValues(alpha: 0.6),
            elevation: 1,
            shadowColor: theme.accentColor.withValues(alpha: 0.18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: isLoading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.onAccentColor,
                    ),
                  ),
                )
              : Text(
                  text,
                  style: TextStyle(
                    color: theme.onAccentColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
        ),
      ),
    );
  }
}

class AuthSecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final ThemeConfig theme;

  const AuthSecondaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.primaryTextColor,
          side: BorderSide(color: context.colors.border, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: theme.primaryTextColor,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Lightweight vector-style illustration used by the welcome/reset/OTP flow.
/// It intentionally contains no mock accounts or simulated provider state.
class AuthIllustration extends StatelessWidget {
  final String type;
  final ThemeConfig theme;
  final double height;

  const AuthIllustration({
    super.key,
    required this.type,
    required this.theme,
    this.height = 180,
  });

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String label) = switch (type) {
      'forgot_password' => (Icons.lock_reset_rounded, 'Reset Access'),
      'otp' => (Icons.verified_user_rounded, 'Secure OTP'),
      _ => (Icons.forum_rounded, 'Fast & Private'),
    };

    return Container(
      height: height,
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.surfaceSecondary.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.accentColor.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: _halo(theme.accentColor, 100),
          ),
          Positioned(
            left: -15,
            bottom: -15,
            child: _halo(theme.accentColor, 90),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: theme.accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: theme.accentColor),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: theme.accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _halo(Color color, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: 0.08),
    ),
  );
}
