import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// A dialog for collecting user feedback and sending it to Sentry
class SentryFeedbackDialog extends StatefulWidget {
  const SentryFeedbackDialog({super.key});

  @override
  State<SentryFeedbackDialog> createState() => _SentryFeedbackDialogState();
}

class _SentryFeedbackDialogState extends State<SentryFeedbackDialog> {
  final _feedbackController = TextEditingController();
  bool _isSubmitting = false;
  String? _submitError;
  final _supportEmail = FirebaseAuth.instance.currentUser?.email;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    final feedbackText = _feedbackController.text.trim();
    if (feedbackText.isEmpty) {
      setState(() => _isSubmitting = false);
      return;
    }

    final userFeedback = SentryFeedback(
      associatedEventId: SentryId.newId(),
      message: feedbackText,
      contactEmail: _supportEmail,
      name: '',
    );

    try {
      await Sentry.captureFeedback(userFeedback);
      if (context.mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thank you for your feedback!')));
      }
    } catch (e) {
      setState(() => _submitError = 'Failed to send feedback. Please try again.');
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // For full-width dialog appearance
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 32),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header (Cancel, Title, Submit)
            Row(
              children: [
                TextButton(
                  onPressed:
                      _isSubmitting
                          ? null
                          : () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).pop(false);
                          },
                  child: const Text('Cancel'),
                  style: TextButton.styleFrom(foregroundColor: Colors.blue),
                ),
                const Spacer(),
                const Text('Feedback & Support', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const Spacer(),
                TextButton(
                  onPressed:
                      _isSubmitting || _feedbackController.text.trim().isEmpty
                          ? null
                          : () {
                            HapticFeedback.lightImpact();
                            _submitFeedback();
                          },
                  child:
                      _isSubmitting
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Submit'),
                  style: TextButton.styleFrom(foregroundColor: Colors.blue),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Input box
            TextField(
              controller: _feedbackController,
              enabled: !_isSubmitting,
              autofocus: true,
              minLines: 6,
              maxLines: null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
                contentPadding: EdgeInsets.all(12),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 18),
            // Support notice
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Be as detailed as possible. We’ll get back to you within\n1 business day to:',
                style: TextStyle(fontSize: 15),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _supportEmail ?? 'No email provided',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            if (_submitError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_submitError!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }
}
