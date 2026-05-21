import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class InviteService {
  static final InviteService instance = InviteService._();
  InviteService._();

  /// Send an email invitation to a member via the device's native email app.
  Future<void> sendEmailInvite({
    required String toEmail,
    required String toName,
    required String groupName,
    required String inviterName,
  }) async {
    final subject = Uri.encodeComponent(
        '$inviterName invited you to "$groupName" on FairShare Club');

    final body = Uri.encodeComponent('''Hi $toName,

$inviterName has added you to the group "$groupName" on FairShare Club!

To access this group and all shared expenses, please:
1. Download FairShare Club app
2. Register using this email address: $toEmail
3. The group "$groupName" will appear automatically after you sign in.

See you there! 🎉

— FairShare Club''');

    final mailtoUri = Uri.parse('mailto:$toEmail?subject=$subject&body=$body');

    if (await canLaunchUrl(mailtoUri)) {
      await launchUrl(mailtoUri);
    } else {
      // Fallback: share via native share sheet
      await Share.share(
        '''Hi $toName! $inviterName has invited you to "$groupName" on FairShare Club.\n\nRegister with $toEmail to join the group automatically. 🎉''',
        subject: 'You\'re invited to $groupName on FairShare Club',
      );
    }
  }

  /// Show a share sheet with an invite message (WhatsApp, SMS, etc.)
  Future<void> shareInvite({
    required String toEmail,
    required String toName,
    required String groupName,
    required String inviterName,
  }) async {
    await Share.share(
      '''Hi $toName! 👋

$inviterName has added you to the group *"$groupName"* on FairShare Club.

To access the group:
1. Download FairShare Club
2. Register using: $toEmail
3. Group will appear automatically ✅

Let's split expenses smartly! 💰''',
      subject: 'Join "$groupName" on FairShare Club',
    );
  }
}

