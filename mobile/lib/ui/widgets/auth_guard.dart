import 'package:banking_app/blocs/auth/auth_bloc.dart';
import 'package:banking_app/services/password_verification_service.dart';
import 'package:banking_app/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Auth Guard Widget - Prevents bypass, user MUST login first
/// 
/// Proteksi Multi-Layer:
/// 1. BlocBuilder: Check auth state secara real-time
/// 2. Auto-redirect: Redirect ke sign-in jika tidak authenticated
/// 3. WillPopScope: Mencegah back button bypass (di child jika perlu)
/// 
/// Usage:
/// ```dart
/// AuthGuard(
///   child: HomePage(),
/// )
/// ```
class AuthGuard extends StatefulWidget {
  final Widget child;
  final Widget? loadingWidget;
  final Widget? unauthenticatedWidget;
  final bool requirePasswordVerified;

  const AuthGuard({
    Key? key,
    required this.child,
    this.loadingWidget,
    this.unauthenticatedWidget,
    this.requirePasswordVerified = true,
  }) : super(key: key);

  @override
  State<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<AuthGuard> {
  bool _hasRedirected = false;

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        // If not authenticated, redirect to sign-in immediately
        // This prevents any bypass attempts
        if (!_hasRedirected && (state is AuthFailed || state is AuthInitial)) {
          _hasRedirected = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushNamedAndRemoveUntil(
              context,
              '/sign-in',
              (route) => false, // Clear all previous routes
            );
          });
        }
      },
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          // Loading state
          if (state is AuthLoading) {
            return widget.loadingWidget ?? const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          final isAuthed = state is AuthSuccess || state is AuthNeedsOnboarding || state is AuthNeedsWalletVerification;

          // Authenticated - optionally check password verification
          if (isAuthed) {
            if (widget.requirePasswordVerified) {
              final isPasswordVerified = PasswordVerificationService().isPasswordVerified();
              if (!isPasswordVerified) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/password-verification',
                    (route) => false,
                  );
                });

                return widget.unauthenticatedWidget ?? Scaffold(
                  backgroundColor: lightBackgroundColor,
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 20),
                        Text(
                          'Verifying wallet password...',
                          style: greyTextStyle,
                        ),
                      ],
                    ),
                  ),
                );
              }
            }

            return WillPopScope(
              onWillPop: () async {
                final currentState = context.read<AuthBloc>().state;
                final stillAuthed =
                    currentState is AuthSuccess || currentState is AuthNeedsOnboarding || currentState is AuthNeedsWalletVerification;
                if (!stillAuthed) {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/sign-in',
                    (route) => false,
                  );
                  return false;
                }

                if (widget.requirePasswordVerified &&
                    !PasswordVerificationService().isPasswordVerified()) {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/password-verification',
                    (route) => false,
                  );
                  return false;
                }

                return true;
              },
              child: widget.child,
            );
          }

          // Not authenticated - show loading while redirecting
          // The listener above will handle the redirect
          return widget.unauthenticatedWidget ?? Scaffold(
            backgroundColor: lightBackgroundColor,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    'Please sign in to continue',
                    style: greyTextStyle,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

