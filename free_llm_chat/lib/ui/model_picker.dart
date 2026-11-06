import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/strings.dart';
import '../data/manifest_cost.dart';
import '../state/model_catalog_controller.dart';
import '../state/settings_controller.dart';
import 'paid_widgets.dart';

/// Opens the model list. `auto` is always first; choosing a specific model skips routing.
Future<void> showModelPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _ModelPickerSheet(),
  );
}

class _ModelPickerSheet extends StatefulWidget {
  const _ModelPickerSheet();

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _subtitle(BuildContext context, ManifestModel m) {
    if (m.isAuto) return context.tr('modelAutoSub');
    switch (m.costClass) {
      case CostClass.paid:
        return priceLine(context, m.cost?.input, m.cost?.output);
      case CostClass.free:
        return context.tr('priceFree');
      case CostClass.unknown:
        return context.tr('priceUnknownShort');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final cat = context.watch<ModelCatalogController>();
    final c = cat.catalog;
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final q = _search.text.trim().toLowerCase();
    final shown = [
      for (final m in c.models)
        if (q.isEmpty || m.id.toLowerCase().contains(q)) m,
    ];

    final String status;
    if (!s.isConfigured) {
      status = context.tr('modelsNotConfigured');
    } else if (!c.available) {
      status = context.tr('modelsUnavailable');
    } else {
      status = context.trf('modelsStatus', {
        'free': '${c.freeCount}',
        'paid': '${c.paidCount}',
        'unknown': '${c.unknownCount}',
      });
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 8, 0),
                child: Row(
                  children: [
                    Expanded(child: Text(context.tr('pickModel'), style: text.titleMedium)),
                    cat.loading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(
                            tooltip: context.tr('refreshModels'),
                            icon: const Icon(Icons.refresh_rounded),
                            onPressed: cat.refresh,
                          ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    status,
                    style: text.bodySmall?.copyWith(
                      color: c.available ? cs.outline : costColor(context, CostClass.unknown),
                    ),
                  ),
                ),
              ),
              if (c.concrete.length > 8)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _search,
                    textDirection: TextDirection.ltr,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      hintText: context.tr('searchModels'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              Flexible(
                child: shown.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(context.tr('noModelsMatch')),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: shown.length,
                        itemBuilder: (ctx, i) {
                          final m = shown[i];
                          final selected = m.id == s.model;
                          return ListTile(
                            dense: true,
                            selected: selected,
                            leading: Icon(
                              m.isAuto ? Icons.auto_awesome : Icons.circle,
                              size: m.isAuto ? 18 : 12,
                              color: m.isAuto ? cs.primary : costColor(ctx, m.costClass),
                            ),
                            title: Text(m.id, textDirection: TextDirection.ltr),
                            subtitle: Text(_subtitle(ctx, m)),
                            trailing: selected ? const Icon(Icons.check) : null,
                            onTap: () {
                              s.setModel(m.id);
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
