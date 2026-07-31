import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String email;
  final Future<bool> Function() onCheckVerification;
  final Future<void> Function() onResend;
  final Future<void> Function() onLogout;

  const EmailVerificationScreen({
    super.key,
    required this.email,
    required this.onCheckVerification,
    required this.onResend,
    required this.onLogout,
  });

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _isChecking = false;
  bool _isResending = false;
  String? _message;
  bool _isError = false;

  Future<void> _check() async {
    setState(() {
      _isChecking = true;
      _message = null;
    });
    try {
      final verified = await widget.onCheckVerification();
      if (!verified && mounted) {
        setState(() {
          _isError = true;
          _message = 'Email is not verified yet. Open the link in your inbox, then try again.';
        });
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() {
          _isError = true;
          _message = error.message ?? 'Could not check verification status.';
        });
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _isResending = true;
      _message = null;
    });
    try {
      await widget.onResend();
      if (mounted) {
        setState(() {
          _isError = false;
          _message = 'Verification email sent. Check your inbox and spam folder.';
        });
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() {
          _isError = true;
          _message = error.code == 'too-many-requests'
              ? 'Too many requests. Wait a moment before resending.'
              : error.message ?? 'Could not resend the verification email.';
        });
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(32),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: Color(0xFFFBBF24),
                  child: Icon(Icons.mark_email_unread_outlined, size: 44, color: Theme.of(context).colorScheme.onPrimary),
                ),
                SizedBox(height: 28),
                Text(
                  'Verify your email',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 26, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                Text(
                  'We sent a verification link to',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15),
                ),
                SizedBox(height: 6),
                Text(
                  widget.email,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFFBBF24), fontSize: 16, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 12),
                Text(
                  'Open the link in your email, then return to Finmo and confirm below.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
                ),
                if (_message != null) ...[
                  SizedBox(height: 18),
                  Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _isError ? Color(0xFFF87171) : Color(0xFF6EE7B7)),
                  ),
                ],
                SizedBox(height: 28),
                FilledButton(
                  onPressed: _isChecking ? null : _check,
                  style: FilledButton.styleFrom(
                    backgroundColor: Color(0xFFFBBF24),
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    minimumSize: Size.fromHeight(52),
                  ),
                  child: Text(_isChecking ? 'Checking...' : "I've verified my email"),
                ),
                SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _isResending ? null : _resend,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    side: BorderSide(color: Theme.of(context).colorScheme.outline),
                    minimumSize: Size.fromHeight(48),
                  ),
                  child: Text(_isResending ? 'Sending...' : 'Resend verification email'),
                ),
                TextButton(
                  onPressed: widget.onLogout,
                  child: Text('Use a different account', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
