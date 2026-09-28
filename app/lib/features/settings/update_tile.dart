import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/common.dart';
import '../../data/repositories/update_repository.dart';

final currentVersionProvider = FutureProvider<int>((ref) => ref.watch(updateRepositoryProvider).currentVersion());

/// "Atualizar aplicativo": confere a última versão e baixa o APK novo, que o
/// Android instala por cima (mesma assinatura), sem perder nada.
class UpdateTile extends ConsumerStatefulWidget {
  const UpdateTile({super.key, this.openUrl});

  /// Para testes; por padrão abre o link no navegador/gerenciador de downloads.
  final Future<bool> Function(Uri url)? openUrl;

  @override
  ConsumerState<UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends ConsumerState<UpdateTile> {
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final update = await ref.read(updateRepositoryProvider).check();
      if (!mounted) return;
      setState(() => _checking = false);
      if (!update.hasUpdate) {
        showMessage(context, 'Você já está na versão mais nova (${update.currentVersion}).');
        return;
      }
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Nova versão disponível'),
          content: Text(
            'Versão ${update.latestVersion} disponível (você tem a ${update.currentVersion}).\n\n'
            'Toque em "Baixar", depois abra o arquivo baixado e confirme "Atualizar". '
            'Seus dados continuam salvos.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Agora não')),
            FilledButton.icon(
              key: const Key('update-download'),
              onPressed: () => Navigator.pop(c, true),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Baixar'),
            ),
          ],
        ),
      );
      if (go != true) return;
      final url = Uri.parse(update.downloadUrl);
      final opened = await (widget.openUrl ?? (u) => launchUrl(u, mode: LaunchMode.externalApplication))(url);
      if (!opened && mounted) showMessage(context, 'Não foi possível abrir o download.', error: true);
    } catch (_) {
      if (mounted) showMessage(context, 'Não foi possível verificar agora. Verifique sua internet.', error: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!canSelfUpdate) return const SizedBox.shrink();
    final version = ref.watch(currentVersionProvider).value;
    return ListTile(
      key: const Key('check-update'),
      leading: _checking
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
          : const Icon(Icons.system_update_rounded),
      title: const Text('Atualizar aplicativo'),
      subtitle: Text(version == null ? 'Verificar se há versão nova' : 'Versão instalada: $version'),
      onTap: _check,
    );
  }
}
