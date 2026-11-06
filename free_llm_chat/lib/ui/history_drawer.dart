import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/strings.dart';
import '../data/models.dart';
import '../state/chat_controller.dart';

class HistoryDrawer extends StatelessWidget {
  const HistoryDrawer({super.key});

  Future<void> _confirmDelete(BuildContext context, ChatController ctrl, Chat chat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(ctx.tr('deleteQ')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('delete'))),
        ],
      ),
    );
    if (ok == true) await ctrl.delete(chat);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ChatController>();
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(context.tr('newChat')),
              onTap: () {
                ctrl.newChat();
                Navigator.pop(context);
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: ctrl.chats.isEmpty
                  ? Center(child: Text(context.tr('noChats')))
                  : ListView.builder(
                      itemCount: ctrl.chats.length,
                      itemBuilder: (ctx, i) {
                        final c = ctrl.chats[i];
                        return ListTile(
                          selected: c.id == ctrl.current?.id,
                          title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            ctrl.open(c);
                            Navigator.pop(ctx);
                          },
                          trailing: IconButton(
                            tooltip: ctx.tr('delete'),
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _confirmDelete(ctx, ctrl, c),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
