import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../generated/l10n/app_localizations.dart';
import 'app_toast.dart';

/// Copies [text] to the system clipboard and shows the themed "copied" toast.
///
/// The shared copy action behind the account-detail address and public-key
/// affordances.
void copyToClipboard(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  AppToast.show(
    context,
    message: AppLocalizations.of(context)!.copiedToClipboard,
  );
}
