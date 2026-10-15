import 'package:flutter/material.dart';

import 'theme.dart';

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => const Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      SizedBox(
        width: 100,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            '2 | S',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 43,
              fontWeight: FontWeight.w300,
              color: gold,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
      SizedBox(width: 18),
      SizedBox(height: 32, child: VerticalDivider()),
      SizedBox(width: 18),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'HOMEWEAR',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 10,
                letterSpacing: 2.4,
                color: muted,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'SALES HUB',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 12,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin = EdgeInsets.zero,
  });
  final Widget child;
  final EdgeInsets padding, margin;
  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: line),
      ),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.8,
        color: muted,
      ),
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, this.tone = 'gold'});
  final String text, tone;
  @override
  Widget build(BuildContext context) {
    final foreground = tone == 'green'
        ? const Color(0xFF416858)
        : tone == 'red'
        ? const Color(0xFF9C5247)
        : tone == 'grey'
        ? muted
        : goldInk;
    final background = tone == 'green'
        ? const Color(0xFFEDF5EF)
        : tone == 'red'
        ? const Color(0xFFFAEEEB)
        : tone == 'grey'
        ? const Color(0xFFF1F0ED)
        : goldWash;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: foreground,
          letterSpacing: .2,
        ),
      ),
    );
  }
}

class EmptyNotice extends StatelessWidget {
  const EmptyNotice({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.search,
  });
  final String title, message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: goldWash,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 28, color: goldInk),
        ),
        const SizedBox(height: 22),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class ErrorNotice extends StatelessWidget {
  const ErrorNotice(this.message, this.retry, {super.key});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: SurfaceCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 30, color: goldInk),
          const SizedBox(height: 16),
          Text(
            'Let’s try that again',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

class LoadingRows extends StatelessWidget {
  const LoadingRows({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading records',
    child: Column(
      children: List.generate(
        5,
        (_) => SurfaceCard(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: canvas,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 10, width: 130, color: canvas),
                    const SizedBox(height: 10),
                    Container(height: 8, width: 90, color: canvas),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void feedback(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
