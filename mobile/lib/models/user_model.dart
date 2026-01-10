class UserModel {
  final String? id;
  final String? name;
  final String? email;
  final String? phoneNumber;
  final String? password;
  final String? username;
  final int? verified;
  final String? profilePicture;
  final String? walletAddress;
  final int? balance;
  final String? cardNumber;
  final String? pin;
  final String? token;

  UserModel({
    this.id,
    this.name,
    this.email,
    this.phoneNumber,
    this.password,
    this.username,
    this.verified,
    this.profilePicture,
    this.walletAddress,
    this.balance,
    this.cardNumber,
    this.pin,
    this.token,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'],
        name: json['name'],
        email: json['email'],
        phoneNumber: json['phone_number'] ?? json['phoneNumber'],
        username: json['username'],
        verified: json['verified'],
        profilePicture: json['profile_picture'] ?? json['profile_photo_url'],
        walletAddress: json['wallet_address'] ?? json['walletAddress'],
        balance: json['balance'],
        cardNumber: json['card_number'],
        pin: json['pin'],
        token: json['token'],
      );

  UserModel copyWith({
    String? username,
    String? name,
    String? email,
    String? phoneNumber,
    String? pin,
    String? password,
    String? walletAddress,
    int? balance,
  }) =>
      UserModel(
        id: id,
        username: username ?? this.username,
        name: name ?? this.name,
        email: email ?? this.email,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        pin: pin ?? this.pin,
        password: password ?? this.password,
        balance: balance ?? this.balance,
        verified: verified,
        profilePicture: profilePicture,
        walletAddress: walletAddress ?? this.walletAddress,
        cardNumber: cardNumber,
        token: token,
      );
}
