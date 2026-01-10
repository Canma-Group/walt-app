part of 'auth_bloc.dart';

@immutable
abstract class AuthEvent extends Equatable {
  const AuthEvent();
  
  @override
  List<Object?> get props => [];
}

class AuthCheckEmail extends AuthEvent {
  final String email;
  const AuthCheckEmail(this.email);

  @override
  List<Object> get props => [email];
}

class AuthRegister extends AuthEvent {
  final SignUpFormModel data;
  const AuthRegister(this.data);

  @override
  List<Object> get props => [data];
}

class AuthLogin extends AuthEvent {
  final SignInFormModel data;
  const AuthLogin(this.data);

  @override
  List<Object> get props => [data];
}

class AuthGetCurrentUser extends AuthEvent {
  const AuthGetCurrentUser();
}

class AuthUpdateUser extends AuthEvent {
  final UserEditFormModel data;
  const AuthUpdateUser(this.data);

  @override
  List<Object> get props => [data];
}

class AuthUpdatePin extends AuthEvent {
  final String oldPin;
  final String newPin;
  const AuthUpdatePin(
    this.oldPin,
    this.newPin,
  );

  @override
  List<Object> get props => [oldPin, newPin];
}

class AuthLogout extends AuthEvent {
  const AuthLogout();
}

class AuthUpdateBalance extends AuthEvent {
  final int amount;
  const AuthUpdateBalance(this.amount);

  @override
  List<Object> get props => [amount];
}

/// Event untuk login dengan Web3Auth + Firebase Google
class AuthLoginWithGoogle extends AuthEvent {
  const AuthLoginWithGoogle();
}

// MetaMask login removed - Gmail is now the only login method