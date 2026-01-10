import 'package:banking_app/models/sign_in_form_model.dart';
import 'package:banking_app/models/sign_up_form_model.dart';
import 'package:banking_app/models/user_edit_form_model.dart';
import 'package:banking_app/models/user_model.dart';
import 'package:banking_app/services/auth_service.dart';
import 'package:banking_app/services/user_service.dart';
import 'package:banking_app/services/wallet_service.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc() : super(AuthInitial()) {
    on<AuthEvent>((event, emit) async {
      if (event is AuthCheckEmail) {
        try {
          emit(AuthLoading());

          final res = await AuthService().checkEmail(event.email);

          if (res == false) {
            emit(AuthCheckEmailSuccess());
          } else {
            emit(const AuthFailed('Email already in use'));
          }
        } catch (e) {
          emit(AuthFailed(e.toString()));
        }
      }

      if (event is AuthRegister) {
        try {
          emit(AuthLoading());

          // Use registerWithPassword for Firebase Auth registration
          final user = await AuthService().registerWithPassword(event.data);

          // After signup, user should verify password on first login
          // Password verification flag is already cleared in sign_up_set_pin_page
          // So user will be redirected to password verification page
          emit(AuthSuccess(user));
        } catch (e) {
          emit(AuthFailed(e.toString()));
        }
      }

      if (event is AuthLogin) {
        try {
          emit(AuthLoading());

          final user = await AuthService().login(event.data);

          emit(AuthSuccess(user));
        } catch (e) {
          emit(AuthFailed(e.toString()));
        }
      }

      if (event is AuthGetCurrentUser) {
        try {
          emit(AuthLoading());

          final result = await AuthService().getCurrentUserStatus();
          final isLoggedIn = result['isLoggedIn'] as bool;
          
          if (!isLoggedIn) {
            emit(const AuthFailed('Please sign in to continue'));
            return;
          }
          
          final user = result['user'] as UserModel?;
          final needsOnboarding = result['needsOnboarding'] as bool? ?? false;
          
          if (user == null) {
            emit(const AuthFailed('User data not found'));
            return;
          }
          
          if (needsOnboarding) {
            emit(AuthNeedsOnboarding(user));
          } else {
            emit(AuthSuccess(user));
          }
        } catch (e) {
          emit(const AuthFailed('Please sign in to continue'));
        }
      }

      if (event is AuthUpdateUser) {
        try {
          if (state is AuthSuccess) {
            final updatedUser = (state as AuthSuccess).user.copyWith(
                  username: event.data.username,
                  name: event.data.name,
                  email: event.data.email,
                  password: event.data.password,
                );

            emit(AuthLoading());

            await UserService().updateUser(event.data);

            emit(AuthSuccess(updatedUser));
          }
        } catch (e) {
          emit(AuthFailed(e.toString()));
        }
      }

      if (event is AuthUpdatePin) {
        try {
          if (state is AuthSuccess) {
            final updatedUser = (state as AuthSuccess).user.copyWith(
                  pin: event.newPin,
                );

            emit(AuthLoading());

            await WalletService().updatePin(
              event.oldPin,
              event.newPin,
            );

            emit(AuthSuccess(updatedUser));
          }
        } catch (e) {
          emit(AuthFailed(e.toString()));
        }
      }

      if (event is AuthLogout) {
        try {
          emit(AuthLoading());

          // Try logout with Google first, fallback to regular logout
          try {
            await AuthService().logoutWithGoogle();
          } catch (e) {
            // Fallback to regular logout if Google logout fails
            await AuthService().logout();
          }

          emit(AuthInitial());
        } catch (e) {
          emit((AuthFailed(e.toString())));
        }
      }

      if (event is AuthUpdateBalance) {
        if (state is AuthSuccess) {
          final currentUser = (state as AuthSuccess).user;
          final updatedUser = currentUser.copyWith(
            balance: currentUser.balance != null ? currentUser.balance! + event.amount : event.amount,
          );

          emit(AuthSuccess(updatedUser));
        }
      }

      // Web3Auth + Firebase Google Login
      if (event is AuthLoginWithGoogle) {
        try {
          emit(AuthLoading());

          final result = await AuthService().loginWithGoogle().timeout(
            const Duration(seconds: 90),
            onTimeout: () {
              throw Exception('Login timeout. Please check your connection and try again.');
            },
          );

          // Check if user is returning (has wallet password & PIN)
          if (result.isReturningUser && !result.needsOnboarding) {
            // Returning user - just needs wallet password verification
            emit(AuthNeedsWalletVerification(result.user));
          } else if (result.needsOnboarding) {
            // New user or incomplete onboarding
            emit(AuthNeedsOnboarding(result.user));
          } else {
            // Fully authenticated
            emit(AuthSuccess(result.user));
          }
        } catch (e, stackTrace) {
          // Extract error message
          String errorMessage = e.toString();
          if (errorMessage.contains('Exception: ')) {
            errorMessage = errorMessage.replaceFirst('Exception: ', '');
          }
          
          emit(AuthFailed(errorMessage));
        }
      }

      // MetaMask login removed - Gmail is now the only login method
    });
  }
}
