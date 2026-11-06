import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/strings.dart';
import '../data/manifest_config.dart';
import '../data/manifest_cost.dart';
import '../data/served_by.dart';
import '../state/chat_controller.dart';
import '../state/model_catalog_controller.dart';
import '../state/settings_controller.dart';

class _Tone {
  const _Tone(this.fg, this.bg);

  final Color fg;
  final Color bg;
}

/// Green = no per-token charge, red = paid, amber = unknown / possibly paid.
_Tone _toneFor(BuildContext context, CostClass c) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (c) {
    CostClass.free => dark
        ? const _Tone(Color(0xFF81C784), Color(0x3381C784))
        : const _Tone(Color(0xFF1B5E20), Color(0x262E7D32)),
    CostClass.paid => dark
        ? const _Tone(Color(0xFFEF9A9A), Color(0x33EF5350))
        : const _Tone(Color(0xFFB71C1C), Color(0x26D32F2F)),
    CostClass.unknown => dark
        ? const _Tone(Color(0xFFFFCC80), Color(0x33FFA726))
        : const _Tone(Color(0xFF8A4B00), Color(0x26F57C00)),
  };
}

/// Color used for a model's billing class in lists.
Color costColor(BuildContext context, CostClass c) => _toneFor(context, c).fg;

/// "$0.75 in / $4.5 out per 1M tokens" (a missing side shows "?").
String priceLine(BuildContext context, double? input, double? output) => context.trf('priceFmt', {
      'in': input == null ? '?' : formatPrice(input),
      'out': output == null ? '?' : formatPrice(output),
    });

/// Badge under the start of every assistant reply: who served it and how it is billed.
class ServedBadge extends StatelessWidget {
  const ServedBadge({super.key, required this.served});

  final ServedBy served;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;

    final _Tone tone;
    final IconData icon;
    final String label;
    if (served.answeredByManifest) {
      tone = _Tone(cs.onSurfaceVariant, cs.surfaceContainerHigh);
      icon = Icons.info_outline;
      label = context.tr('badgeManifestSelf');
    } else if (served.headersMissing) {
      tone = _toneFor(context, CostClass.unknown);
      icon = Icons.help_outline;
      label = context.tr('badgeServedUnknown');
    } else {
      tone = _toneFor(context, served.costClass);
      switch (served.costClass) {
        case CostClass.free:
          icon = Icons.check_circle_outline;
          label = context.tr('badgeFree');
        case CostClass.paid:
          icon = Icons.paid_outlined;
          final hasPrice = served.inputPrice != null || served.outputPrice != null;
          label = hasPrice
              ? '${context.tr('badgePaid')} · ${priceLine(context, served.inputPrice, served.outputPrice)}'
              : context.tr('badgePaid');
        case CostClass.unknown:
          icon = Icons.warning_amber_rounded;
          label = context.tr(served.listUnavailable
              ? 'badgeUnknownNoList'
              : served.ambiguous
                  ? 'badgeAmbiguous'
                  : 'badgeUnknown');
      }
    }

    final modelText = served.model == null
        ? null
        : (served.provider == null || served.answeredByManifest
            ? served.model!
            : '${served.provider} · ${served.model}');

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tone.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: tone.fg),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        label,
                        style: small?.copyWith(color: tone.fg, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              if (modelText != null && !served.answeredByManifest)
                Text(
                  modelText,
                  textDirection: TextDirection.ltr,
                  style: small?.copyWith(color: cs.outline),
                ),
            ],
          ),
          if (served.fallbackFrom != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_horiz_rounded, size: 14, color: cs.outline),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${context.tr('fellBackFrom')} ${served.fallbackFrom}',
                      textDirection: TextDirection.ltr,
                      style: small?.copyWith(color: cs.outline),
                    ),
                  ),
                ],
              ),
            ),
          if (served.estimatedCostUsd != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                context.trf('estimatedCost', {'cost': formatCost(served.estimatedCostUsd!)}),
                style: small?.copyWith(color: tone.fg),
              ),
            ),
        ],
      ),
    );
  }
}

/// Persistent notice above the composer while the `auto` model is selected and the
/// model list contains paid or price-unknown models (or could not be loaded).
class PaidAutoNotice extends StatelessWidget {
  const PaidAutoNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final cat = context.watch<ModelCatalogController>();
    if (!s.isConfigured || !s.warnPaid || s.model != kAutoModel || !cat.hasAttempted) {
      return const SizedBox.shrink();
    }
    final c = cat.catalog;
    if (!c.hasPaidOrUnknown) return const SizedBox.shrink();

    final tone = _toneFor(context, CostClass.unknown);
    final small = Theme.of(context).textTheme.bodySmall;
    final detail = c.available
        ? context.trf('autoNoticeCounts', {
            'paid': '${c.paidCount}',
            'unknown': '${c.unknownCount}',
            'total': '${c.concrete.length}',
          })
        : context.tr('autoNoticeNoList');
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: tone.fg),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('autoNotice'),
                    style: small?.copyWith(color: tone.fg, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(detail, style: small?.copyWith(color: tone.fg)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown before sending to a specific model that is paid or whose price is unknown.
class PaidDialog extends StatelessWidget {
  const PaidDialog({super.key, required this.warning});

  final PaidWarning warning;

  @override
  Widget build(BuildContext context) {
    final paid = warning.costClass == CostClass.paid;
    final tone = _toneFor(context, paid ? CostClass.paid : CostClass.unknown);
    final String body;
    if (paid) {
      body = context.trf('paidBody',
          {'price': priceLine(context, warning.cost?.input, warning.cost?.output)});
    } else {
      body = context.tr(warning.listUnavailable ? 'unknownBodyNoList' : 'unknownBody');
    }
    return AlertDialog(
      icon: Icon(paid ? Icons.paid_outlined : Icons.warning_amber_rounded, color: tone.fg),
      title: Text(context.tr(paid ? 'paidTitle' : 'unknownTitle')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            warning.model,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(body),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, PaidDecision.cancel),
          child: Text(context.tr('cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, PaidDecision.switchToAuto),
          child: Text(context.tr('switchAutoSend')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, PaidDecision.sendOnce),
          child: Text(context.tr('sendOnce')),
        ),
      ],
    );
  }
}
