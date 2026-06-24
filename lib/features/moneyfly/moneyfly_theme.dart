import 'package:flutter/material.dart';

class MoneyflyColors {
  const MoneyflyColors._();

  static const bg = Color(0xfffbfcfd);
  static const ink = Color(0xff121820);
  static const muted = Color(0xff657282);
  static const line = Color(0xffdce4ec);
  static const soft = Color(0xfff1f5f8);
  static const blue = Color(0xff1769d4);
  static const green = Color(0xff18a66a);
  static const amber = Color(0xffb7791f);
  static const red = Color(0xffd64242);
  static const dark = Color(0xff1d2733);
}

class MoneyflyPage extends StatelessWidget {
  const MoneyflyPage({
    super.key,
    required this.title,
    required this.child,
    this.actions,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MoneyflyColors.bg,
      appBar: AppBar(
        title: Text(title),
        actions: actions,
        backgroundColor: MoneyflyColors.bg,
        foregroundColor: MoneyflyColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(child: child),
    );
  }
}

class MoneyflyPanel extends StatelessWidget {
  const MoneyflyPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = Colors.white,
    this.borderColor = MoneyflyColors.line,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class MoneyflyEmptyState extends StatelessWidget {
  const MoneyflyEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: MoneyflyPanel(
          color: MoneyflyColors.soft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: MoneyflyColors.blue, size: 36),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MoneyflyColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: MoneyflyColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MoneyflySectionTitle extends StatelessWidget {
  const MoneyflySectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: MoneyflyColors.ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class MoneyflyStatusPill extends StatelessWidget {
  const MoneyflyStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

ButtonStyle moneyflyPrimaryButtonStyle() {
  return FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(46),
    backgroundColor: MoneyflyColors.blue,
    foregroundColor: Colors.white,
    shape: const StadiumBorder(),
    textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0),
  );
}

ButtonStyle moneyflyDarkButtonStyle() {
  return FilledButton.styleFrom(
    backgroundColor: MoneyflyColors.dark,
    foregroundColor: Colors.white,
    shape: const StadiumBorder(),
    textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0),
  );
}
