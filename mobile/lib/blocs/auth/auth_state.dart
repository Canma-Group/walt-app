part of 'auth_bloc.dart';

@immutable
abstract class AuthState extends Equatable {
  const AuthState();
  
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthFailed extends AuthState {
  final String e;
  const AuthFailed(this.e);

  @override
  List<Object> get props => [e];
}

class AuthCheckEmailSuccess extends AuthState {}

class AuthSuccess extends AuthState {
  final UserModel user;
  const AuthSuccess(this.user);

  @override
  List<Object> get props => [user];
}

/// User is authenticated with Google, but must complete onboarding
/// (phone, full name, profile photo, wallet password, wallet PIN, wallet id)
class AuthNeedsOnboarding extends AuthState {
  final UserModel user;
  const AuthNeedsOnboarding(this.user);

  @override
  List<Object> get props => [user];
}

/// User is a returning user who has completed onboarding before.
/// They just need to verify their wallet password to continue.
class AuthNeedsWalletVerification extends AuthState {
  final UserModel user;
  const AuthNeedsWalletVerification(this.user);

  @override
  List<Object> get props => [user];
}