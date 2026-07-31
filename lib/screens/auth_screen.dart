import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// Sign In / Sign Up toggle uses phone number as key
class AuthScreen extends StatefulWidget {
  final Future<void> Function(String email, String password) onSignIn;
  final Future<void> Function(String email, String phone, String password) onSignUp;
  final Future<bool> Function() onGoogleSignIn;
  final Future<void> Function(String phone) onCreateGoogleProfile;
  final String? initialError;

  const AuthScreen({
    super.key,
    required this.onSignIn,
    required this.onSignUp,
    required this.onGoogleSignIn,
    required this.onCreateGoogleProfile,
    this.initialError,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isSignUp = false;
  bool _showPassword = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _errorMessage = widget.initialError;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (email.isEmpty || password.isEmpty || (_isSignUp && phone.isEmpty) || (_isSignUp && confirmPassword.isEmpty)) {
      setState(() => _errorMessage = 'Please fill in all fields.');
      return;
    }

    if (_isSignUp && password != confirmPassword) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      if (_isSignUp) {
        await widget.onSignUp(email, phone, password);
      } else {
        await widget.onSignIn(email, password);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Something went wrong. Please try again.');
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final needsProfile = await widget.onGoogleSignIn();
      if (!needsProfile || !mounted) return;

      var phoneInput = _phoneController.text.trim();
      final phone = await showDialog<String?>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Complete your Finmo profile'),
          content: TextFormField(
            initialValue: phoneInput,
            onChanged: (value) => phoneInput = value.trim(),
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Phone number',
              helperText: 'This is requested only for your first sign-in',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, phoneInput),
              child: Text('Continue'),
            ),
          ],
        ),
      );
      if (phone == null || phone.isEmpty) return;
      await widget.onCreateGoogleProfile(phone);
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Google sign-in failed.');
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Color(0xFFFBBF24)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(32),
          child: Column(
            children: [
              SizedBox(height: 24),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(color: Color(0xFFFBBF24), shape: BoxShape.circle),
                child: Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, shape: BoxShape.circle),
                    child: Center(
                      child: Text(
                        'Finmo',
                        style: TextStyle(
                          color: Color(0xFFFBBF24),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 32),
              Text(
                _isSignUp ? 'Create Account' : 'Welcome Back',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                _isSignUp ? 'Sign up to manage your Finmo finances' : 'Sign in to manage your Finmo finances',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
              ),
              SizedBox(height: 32),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Email', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14)),
              ),
              SizedBox(height: 8),
              TextField(
                controller: _emailController,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: _inputDecoration('you@example.com'),
              ),
              SizedBox(height: 20),
              if (_isSignUp) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Phone Number', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14)),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: _phoneController,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
                  keyboardType: TextInputType.phone,
                  decoration: _inputDecoration('+250 78X XXX XXX'),
                ),
                SizedBox(height: 20),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Password', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14)),
              ),
              SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
                obscureText: !_showPassword,
                decoration: _inputDecoration('Enter your password').copyWith(
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              if (_isSignUp) ...[
                SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Confirm Password', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14)),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: _confirmPasswordController,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
                  obscureText: !_showPassword,
                  decoration: _inputDecoration('Re-enter your password'),
                ),
              ],
              if (_errorMessage != null) ...[
                SizedBox(height: 16),
                Text(_errorMessage!, style: TextStyle(color: Color(0xFFF87171), fontSize: 13)),
              ],
              SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFFBBF24),
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSubmitting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        )
                      : Text(
                          _isSignUp ? 'Sign Up' : 'Sign In',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
              SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: Divider(color: Theme.of(context).colorScheme.outline)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('OR', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                  ),
                  Expanded(child: Divider(color: Theme.of(context).colorScheme.outline)),
                ],
              ),
              SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isSubmitting ? null : _handleGoogleSignIn,
                  icon: Text(
                    'G',
                    style: TextStyle(color: Color(0xFF4285F4), fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  label: Text('Continue with Google'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    side: BorderSide(color: Theme.of(context).colorScheme.outline),
                    padding: EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isSignUp ? 'Already have an account? ' : "Need an account? ",
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
                  ),
                  GestureDetector(
                    onTap: () => setState(() {
                      _isSignUp = !_isSignUp;
                      _errorMessage = null;
                    }),
                    child: Text(
                      _isSignUp ? 'Sign In' : 'Sign Up',
                      style: TextStyle(color: Color(0xFFFBBF24), fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
