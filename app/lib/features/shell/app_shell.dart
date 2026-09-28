import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../audio/audio_record_sheet.dart';
import '../auth/auth_widgets.dart';

class _Destination {
  const _Destination(this.path, this.label, this.icon, this.selectedIcon);
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Destination('/', 'Dashboard', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
  _Destination('/transactions', 'Movimentações', Icons.receipt_long_outlined, Icons.receipt_long_rounded),
  _Destination('/budget', 'Orçamento', Icons.donut_large_outlined, Icons.donut_large_rounded),
  _Destination('/planning', 'Planejamento', Icons.event_note_outlined, Icons.event_note_rounded),
  _Destination('/insights', 'Análises', Icons.insights_outlined, Icons.insights_rounded),
  _Destination('/goals', 'Metas', Icons.flag_outlined, Icons.flag_rounded),
  _Destination('/settings', 'Configurações', Icons.settings_outlined, Icons.settings_rounded),
];

/// Itens da barra inferior no celular; o restante fica em "Mais".
const _mobileMain = ['/', '/transactions', '/budget'];

/// Menu lateral no desktop/tablet, barra inferior + botão "+" no celular.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child, required this.location});
  final Widget child;
  final String location;

  static const desktopBreakpoint = 1000.0;
  static const tabletBreakpoint = 640.0;

  int get _index {
    final i = _destinations.indexWhere((d) => d.path == location);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= tabletBreakpoint) return _wide(context, extended: width >= desktopBreakpoint);
    return _mobile(context);
  }

  Widget _wide(BuildContext context, {required bool extended}) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: extended ? 248 : 88,
            color: Theme.of(context).cardTheme.color,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(extended ? 20 : 12, 20, extended ? 20 : 12, 16),
                    child: extended
                        ? const AppLogo()
                        : Icon(Icons.account_balance_wallet_rounded, color: scheme.primary, size: 32),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: extended ? 16 : 12),
                    child: extended
                        ? Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  key: const Key('sidebar-record'),
                                  onPressed: () => showAudioRecorderSheet(context),
                                  icon: const Icon(Icons.mic_rounded),
                                  label: const Text('Gravar áudio'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () => showAddTransactionSheet(context),
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('Nova movimentação'),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              FloatingActionButton(
                                heroTag: 'rail-record',
                                tooltip: 'Gravar áudio',
                                onPressed: () => showAudioRecorderSheet(context),
                                child: const Icon(Icons.mic_rounded),
                              ),
                              const SizedBox(height: 8),
                              IconButton.filledTonal(
                                tooltip: 'Nova movimentação',
                                onPressed: () => showAddTransactionSheet(context),
                                icon: const Icon(Icons.add_rounded),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: NavigationRail(
                      extended: extended,
                      backgroundColor: Colors.transparent,
                      selectedIndex: _index,
                      labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                      onDestinationSelected: (i) => context.go(_destinations[i].path),
                      destinations: [
                        for (final d in _destinations)
                          NavigationRailDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.selectedIcon),
                            label: Text(d.label),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _mobile(BuildContext context) {
    final mainIndex = _mobileMain.indexOf(location);
    return Scaffold(
      body: child,
      floatingActionButton: FloatingActionButton(
        key: const Key('fab-add'),
        tooltip: 'Adicionar',
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        onPressed: () => showAddTransactionSheet(context),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: NavigationBar(
        selectedIndex: mainIndex < 0 ? 3 : mainIndex,
        onDestinationSelected: (i) {
          if (i < _mobileMain.length) {
            context.go(_mobileMain[i]);
          } else {
            _showMore(context);
          }
        },
        destinations: [
          for (final path in _mobileMain)
            () {
              final d = _destinations.firstWhere((d) => d.path == path);
              return NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: path == '/' ? 'Início' : d.label,
              );
            }(),
          const NavigationDestination(icon: Icon(Icons.menu_rounded), label: 'Mais'),
        ],
      ),
    );
  }

  void _showMore(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final d in _destinations.where((d) => !_mobileMain.contains(d.path)))
              ListTile(
                leading: Icon(d.icon),
                title: Text(d.label),
                selected: d.path == location,
                onTap: () {
                  Navigator.pop(sheet);
                  context.go(d.path);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Menu do botão "+": gravar áudio (destaque), receita, despesa, transferência.
Future<void> showAddTransactionSheet(BuildContext context) {
  final colors = context.financeColors;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) {
      void open(String type) {
        Navigator.pop(sheet);
        context.push('/transactions/new?type=$type');
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                key: const Key('add-audio'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 64)),
                onPressed: () {
                  Navigator.pop(sheet);
                  showAudioRecorderSheet(context);
                },
                icon: const Icon(Icons.mic_rounded, size: 28),
                label: const Text('Gravar áudio', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 8),
              Text(
                'Fale naturalmente: "Gastei 45 reais no almoço hoje".',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              _AddOption(
                icon: Icons.arrow_downward_rounded,
                color: colors.income,
                label: 'Adicionar receita',
                onTap: () => open('income'),
              ),
              _AddOption(
                icon: Icons.arrow_upward_rounded,
                color: colors.expense,
                label: 'Adicionar despesa',
                onTap: () => open('expense'),
              ),
              _AddOption(
                icon: Icons.swap_horiz_rounded,
                color: colors.transfer,
                label: 'Transferir',
                onTap: () => open('transfer'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _AddOption extends StatelessWidget {
  const _AddOption({required this.icon, required this.color, required this.label, required this.onTap});
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.14),
        child: Icon(icon, color: color),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
