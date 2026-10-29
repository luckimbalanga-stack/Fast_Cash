import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/version.dart';
import '../theme/app_theme.dart';

Future<void> showAppUpdateDialog(BuildContext context, AppUpdateInfo update) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !update.forced,
    builder: (dialogContext) {
      return PopScope(
        canPop: !update.forced,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Mise à jour disponible', style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(update.message, style: const TextStyle(color: AppColors.muted, height: 1.4)),
              const SizedBox(height: 12),
              Text('Version installée : ${update.currentVersion}', style: const TextStyle(fontSize: 13)),
              Text(
                'Nouvelle version : ${update.latestVersion}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              if (update.forced) ...[
                const SizedBox(height: 10),
                const Text(
                  'Cette mise à jour est obligatoire pour continuer à utiliser Fast-Cash.',
                  style: TextStyle(color: AppColors.danger, fontSize: 13, height: 1.35),
                ),
              ],
            ],
          ),
          actions: [
            if (!update.forced)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Plus tard'),
              ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              ),
              onPressed: () async {
                final uri = Uri.tryParse(update.downloadUrl);
                if (uri == null) return;
                final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                if (!ok && dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Impossible d’ouvrir le lien de téléchargement.'),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Télécharger'),
            ),
          ],
        ),
      );
    },
  );
}
