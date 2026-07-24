import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Sign In / Sign Up toggle. Rebuilt from `LoginScreen.tsx` — the original's
/// dead "Sign Up" link is now a real mode switch. Sign Up additionally
/// collects a phone number, which is the key the rest of the local schema
/// and Firestore documents are built around.
class AuthScreen extends StatefulWidget {
  final Future<void> Function(String email, String password) onSignIn;
  final Future<void> Function(String email, String phone, String password) onSignUp;

  const AuthScreen({super.key, required this.onSignIn, required this.onSignUp});

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
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF6B7280)),
      filled: true,
      fillColor: const Color(0xFF1F2937),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF374151)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF374151)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFBBF24)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(color: Color(0xFFFBBF24), shape: BoxShape.circle),
                child: Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(color: Color(0xFF111827), shape: BoxShape.circle),
                    child: const Center(
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
              const SizedBox(height: 32),
              Text(
                _isSignUp ? 'Create Account' : 'Welcome Back',
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _isSignUp ? 'Sign up to manage your Finmo finances' : 'Sign in to manage your Finmo finances',
                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
              ),
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Email', style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 14)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: _inputDecoration('you@example.com'),
              ),
              const SizedBox(height: 20),
              if (_isSignUp) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Phone Number', style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 14)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneController,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  keyboardType: TextInputType.phone,
                  decoration: _inputDecoration('+250 78X XXX XXX'),
                ),
                const SizedBox(height: 20),
              ],
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Password', style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 14)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                obscureText: !_showPassword,
                decoration: _inputDecoration('Enter your password').copyWith(
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                      color: const Color(0xFF9CA3AF),
                    ),
                  ),
                ),
              ),
              if (_isSignUp) ...[
                const SizedBox(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Confirm Password', style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 14)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _confirmPasswordController,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  obscureText: !_showPassword,
                  decoration: _inputDecoration('Re-enter your password'),
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(_errorMessage!, style: const TextStyle(color: Color(0xFFF87171), fontSize: 13)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFBBF24),
                    foregroundColor: const Color(0xFF111827),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF111827)),
                        )
                      : Text(
                          _isSignUp ? 'Sign Up' : 'Sign In',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isSignUp ? 'Already have an account? ' : "Need an account? ",
                    style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                  ),
                  GestureDetector(
                    onTap: () => setState(() {
                      _isSignUp = !_isSignUp;
                      _errorMessage = null;
                    }),
                    child: Text(
                      _isSignUp ? 'Sign In' : 'Sign Up',
                      style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 14, fontWeight: FontWeight.w600),
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