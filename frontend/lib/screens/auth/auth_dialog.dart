import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cacao/models/models.dart';
import 'package:cacao/providers/state.dart';
import 'package:cacao/routes/app_routes.dart';
import 'package:cacao/routes/portal.dart';
import 'package:cacao/services/api_service.dart';
import 'package:cacao/theme.dart';
import 'package:cacao/widgets/modal_frame.dart';

/// Login / Register dialog. Opens the role-based portal after sign-in.
class AuthDialog extends ConsumerStatefulWidget {
  const AuthDialog({super.key});

  @override
  ConsumerState<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends ConsumerState<AuthDialog> {
  bool _login = true;
  bool _hidePw = true;
  bool _busy = false;
  String _error = '';
  String _info = '';
  bool _consent = false;

  final _lEmail = TextEditingController();
  final _lPass = TextEditingController();
  final _rName = TextEditingController();
  final _rEmail = TextEditingController();
  final _rPass = TextEditingController();
  final _rConfirm = TextEditingController();

  @override
  void dispose() {
    for (final c in [_lEmail, _lPass, _rName, _rEmail, _rPass, _rConfirm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _openPortal(NavigatorState nav, AppUser user) {
    nav.pop();
    nav.push(AppRoutes.page(buildPortal(user)));
  }

  /// Pulls the full account list so the admin portal shows real users.
  Future<void> _loadAdminUsers() async {
    try {
      await refreshUsers(ref);
    } catch (_) {
      // Keep whatever we already had - the admin list is not critical here.
    }
  }

  Future<void> _doLogin() async {
    final email = _lEmail.text.trim();
    if (email.isEmpty || _lPass.text.isEmpty) {
      return setState(() => _error = 'Enter your email and password.');
    }

    setState(() {
      _busy = true;
      _error = '';
      _info = '';
    });

    try {
      final user = await CacaoApi.login(email: email, password: _lPass.text);
      if (!mounted) return;
      ref.read(authProvider.notifier).signIn(user);
      if (user.role == 'Admin') _loadAdminUsers();
      _openPortal(Navigator.of(context), user);
    } on ApiException catch (err) {
      if (mounted) setState(() => _error = err.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doRegister() async {
    final name = _rName.text.trim();
    final email = _rEmail.text.trim();
    if (name.isEmpty || !email.contains('@')) {
      return setState(() => _error = 'Enter your name and a valid email.');
    }
    if (_rPass.text.length < 8) {
      return setState(() => _error = 'Password must be at least 8 characters.');
    }
    if (_rPass.text != _rConfirm.text) {
      return setState(() => _error = 'Passwords do not match.');
    }
    if (!_consent) {
      return setState(
        () => _error = 'Please accept the terms and privacy notice.',
      );
    }

    setState(() {
      _busy = true;
      _error = '';
      _info = '';
    });

    try {
      await CacaoApi.register(
        fullName: name,
        email: email,
        password: _rPass.text,
      );
      if (!mounted) return;
      setState(() {
        _login = true;
        _lEmail.text = email;
        _lPass.clear();
        _rName.clear();
        _rEmail.clear();
        _rPass.clear();
        _rConfirm.clear();
        _consent = false;
        _info = 'Account created! Please log in.';
      });
    } on ApiException catch (err) {
      if (mounted) setState(() => _error = err.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String label, IconData icon, {Widget? suffix}) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    final eye = IconButton(
      icon: Icon(
        _hidePw ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 20,
      ),
      onPressed: () => setState(() => _hidePw = !_hidePw),
    );

    return ModalFrame(
      maxWidth: 460,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Login')),
                ButtonSegment(value: false, label: Text('Register')),
              ],
              selected: {_login},
              onSelectionChanged: (s) => setState(() {
                _login = s.first;
                _error = '';
                _info = '';
              }),
            ),
            const SizedBox(height: 20),
            Text(
              _login ? 'Welcome back.' : 'Create account.',
              style: GoogleFonts.playfairDisplay(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.brown800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _login
                  ? 'Sign in to analyze cacao and manage your batch records.'
                  : 'Create your CacaoGrade AI account to save analysis records.',
              style: const TextStyle(color: AppColors.mutedBrown, fontSize: 13),
            ),
            const SizedBox(height: 18),
            if (_login) ...[
              TextField(
                controller: _lEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: _dec('Email address', Icons.mail_outline),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _lPass,
                obscureText: _hidePw,
                decoration: _dec('Password', Icons.lock_outline, suffix: eye),
              ),
            ] else ...[
              TextField(
                controller: _rName,
                decoration: _dec('Full name', Icons.person_outline),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: _dec('Email address', Icons.mail_outline),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rPass,
                obscureText: _hidePw,
                decoration: _dec(
                  'Password (min. 8 characters)',
                  Icons.lock_outline,
                  suffix: eye,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rConfirm,
                obscureText: _hidePw,
                decoration: _dec('Confirm password', Icons.lock_outline),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.cream2,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppColors.mutedBrown,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your access role (Farmer, Staff or Admin) is assigned by the administrator.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.mutedBrown,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _consent,
                onChanged: (v) => setState(() => _consent = v ?? false),
                title: const Text(
                  'I agree to the system terms and privacy notice.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
            if (_info.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _info,
                  style: const TextStyle(color: AppColors.green, fontSize: 12),
                ),
              ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error,
                  style: const TextStyle(color: AppColors.red, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : (_login ? _doLogin : _doRegister),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6D469B),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: const StadiumBorder(),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _login ? 'Log In' : 'Create Account',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
