import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// Near Sync Service
/// 
/// Handles location-based user discovery for wallet contacts.
/// Users can enable "Near Sync" mode to find other wallet users nearby.
class NearSyncService {
  static final NearSyncService _instance = NearSyncService._internal();
  factory NearSyncService() => _instance;
  NearSyncService._internal();

  // Firebase Realtime Database with explicit URL for asia-southeast1 region
  static const String _databaseUrl = 'https://canma-wallet-default-rtdb.asia-southeast1.firebasedatabase.app';
  late final FirebaseDatabase _realtimeDb;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _dbInitialized = false;
  
  bool _isEnabled = false;
  String? _currentUserId;
  String? _currentWalletAddress;
  Position? _lastPosition;
  StreamSubscription<Position>? _positionStream;
  Timer? _cleanupTimer;
  
  // Radius in kilometers for nearby search
  static const double defaultRadiusKm = 5.0;
  
  // How often to update location (in seconds)
  static const int locationUpdateInterval = 30;
  
  // How long before a user is considered "offline" (in minutes)
  // Increased to 15 minutes for better user experience
  static const int offlineThresholdMinutes = 15;

  bool get isEnabled => _isEnabled;
  Position? get lastPosition => _lastPosition;

  /// Initialize the service with user data
  Future<void> initialize({
    required String userId,
    required String walletAddress,
  }) async {
    print('[NearSync] 🔧 Initializing service...');
    print('[NearSync]   userId: $userId');
    print('[NearSync]   walletAddress: $walletAddress');
    
    // Initialize Firebase Realtime Database with explicit URL
    if (!_dbInitialized) {
      print('[NearSync] 🔥 Initializing Firebase Realtime Database...');
      print('[NearSync]   Database URL: $_databaseUrl');
      _realtimeDb = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: _databaseUrl,
      );
      _dbInitialized = true;
      print('[NearSync] ✅ Firebase Realtime Database initialized');
    }
    
    _currentUserId = userId;
    _currentWalletAddress = walletAddress;
    print('[NearSync] ✅ Service initialized');
  }

  /// Check and request location permissions
  Future<bool> checkPermissions() async {
    print('[NearSync] 📍 Checking location permissions...');
    
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    print('[NearSync]   Location service enabled: $serviceEnabled');
    if (!serviceEnabled) {
      print('[NearSync] ❌ Location service is disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    print('[NearSync]   Current permission: $permission');
    
    if (permission == LocationPermission.denied) {
      print('[NearSync]   Requesting permission...');
      permission = await Geolocator.requestPermission();
      print('[NearSync]   Permission after request: $permission');
      if (permission == LocationPermission.denied) {
        print('[NearSync] ❌ Permission denied by user');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('[NearSync] ❌ Permission denied forever');
      return false;
    }

    print('[NearSync] ✅ Location permissions granted');
    return true;
  }

  /// Enable Near Sync mode - starts broadcasting location
  Future<bool> enable() async {
    print('[NearSync] 🚀 Enabling Near Sync...');
    
    if (_currentUserId == null || _currentWalletAddress == null) {
      print('[NearSync] ❌ Service not initialized');
      throw Exception('Service not initialized. Call initialize() first.');
    }

    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      print('[NearSync] ❌ No location permission');
      return false;
    }

    // Get current position with timeout and high accuracy
    print('[NearSync] 📡 Getting current position (timeout: 30s, HIGH accuracy)...');
    try {
      _lastPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best, // Use BEST accuracy for real GPS
          timeLimit: Duration(seconds: 30), // More time for GPS lock
        ),
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () async {
          print('[NearSync] ⏱️ Position timeout, trying last known position...');
          // Try to get last known position as fallback
          final lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null) {
            print('[NearSync] 📍 Using last known position: ${lastKnown.latitude}, ${lastKnown.longitude}');
            return lastKnown;
          }
          throw Exception('GPS timeout and no last known position');
        },
      );
      print('[NearSync] ✅ Position obtained: ${_lastPosition!.latitude}, ${_lastPosition!.longitude}');
    } catch (e) {
      print('[NearSync] ❌ Error getting position: $e');
      // Try last known position as final fallback
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          print('[NearSync] 📍 Fallback to last known: ${lastKnown.latitude}, ${lastKnown.longitude}');
          _lastPosition = lastKnown;
        } else {
          print('[NearSync] ❌ No position available');
          return false;
        }
      } catch (e2) {
        print('[NearSync] ❌ Fallback also failed: $e2');
        return false;
      }
    }

    // Update location in Firebase Realtime Database
    print('[NearSync] 💾 Updating location in Firebase...');
    await _updateLocation(_lastPosition!);

    // Start listening to position changes
    print('[NearSync] 👂 Starting position stream...');
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 100, // Update every 100 meters
      ),
    ).listen((Position position) {
      print('[NearSync] 📍 Position updated: ${position.latitude}, ${position.longitude}');
      _lastPosition = position;
      _updateLocation(position);
    });

    // Start cleanup timer to remove stale entries
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _cleanupStaleEntries(),
    );

    _isEnabled = true;
    print('[NearSync] ✅ Near Sync enabled successfully');
    return true;
  }

  /// Disable Near Sync mode - stops broadcasting and removes from database
  Future<void> disable() async {
    print('[NearSync] 🛑 Disabling Near Sync...');
    _isEnabled = false;
    
    // Cancel position stream
    await _positionStream?.cancel();
    _positionStream = null;
    print('[NearSync]   Position stream cancelled');
    
    // Cancel cleanup timer
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    print('[NearSync]   Cleanup timer cancelled');

    // Remove from realtime database
    if (_currentUserId != null) {
      try {
        print('[NearSync] 🗑️ Removing from database...');
        await _realtimeDb.ref('near_sync/$_currentUserId').remove();
        print('[NearSync] ✅ Removed from database');
      } catch (e) {
        print('[NearSync] ❌ Error removing from database: $e');
      }
    }
    print('[NearSync] ✅ Near Sync disabled');
  }

  /// Update user location in Firebase Realtime Database
  Future<void> _updateLocation(Position position) async {
    if (_currentUserId == null) {
      print('[NearSync] ⚠️ Cannot update location: userId is null');
      return;
    }

    try {
      print('[NearSync] 👤 Fetching user profile from Firestore...');
      final userDoc = await _firestore.collection('users').doc(_currentUserId).get();
      final userData = userDoc.data() ?? {};
      print('[NearSync]   User data: ${userData['name'] ?? userData['username'] ?? 'Anonymous'}');

      final locationData = {
        'userId': _currentUserId,
        'walletAddress': _currentWalletAddress,
        'name': userData['name'] ?? userData['username'] ?? 'Anonymous',
        'profilePicture': userData['profile_picture'] ?? userData['profile_photo_url'],
        'latitude': position.latitude,
        'longitude': position.longitude,
        'lastUpdated': ServerValue.timestamp,
        'isOnline': true,
      };
      
      print('[NearSync] 💾 Writing to Firebase Realtime DB: near_sync/$_currentUserId');
      print('[NearSync]   Data: $locationData');
      
      await _realtimeDb.ref('near_sync/$_currentUserId').set(locationData);
      print('[NearSync] ✅ Location updated successfully in Firebase');
    } catch (e) {
      print('[NearSync] ❌ Error updating location: $e');
      print('[NearSync]   Error type: ${e.runtimeType}');
      if (e is FirebaseException) {
        print('[NearSync]   Firebase error code: ${e.code}');
        print('[NearSync]   Firebase error message: ${e.message}');
      }
    }
  }

  /// Clean up stale entries (users who haven't updated in a while)
  Future<void> _cleanupStaleEntries() async {
    // This is handled by Firebase Rules or Cloud Functions in production
    // For now, we just ensure our own entry is fresh
    if (_isEnabled && _lastPosition != null) {
      await _updateLocation(_lastPosition!);
    }
  }

  /// Get list of nearby users within specified radius
  Future<List<NearbyUser>> getNearbyUsers({double radiusKm = defaultRadiusKm}) async {
    print('[NearSync] 🔍 Searching for nearby users (radius: ${radiusKm}km)...');
    
    if (_lastPosition == null) {
      print('[NearSync]   No cached position, getting current position...');
      try {
        _lastPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
          ),
        );
        print('[NearSync]   Position: ${_lastPosition!.latitude}, ${_lastPosition!.longitude}');
      } catch (e) {
        print('[NearSync] ❌ Error getting position: $e');
        return [];
      }
    }

    final List<NearbyUser> nearbyUsers = [];
    final cutoffTime = DateTime.now().subtract(
      const Duration(minutes: offlineThresholdMinutes),
    ).millisecondsSinceEpoch;

    try {
      print('[NearSync] 📡 Querying Firebase Realtime DB: near_sync/');
      final snapshot = await _realtimeDb.ref('near_sync').get();
      print('[NearSync]   Snapshot exists: ${snapshot.exists}');
      print('[NearSync]   Snapshot value: ${snapshot.value}');
      
      if (snapshot.exists && snapshot.value != null) {
        print('[NearSync]   Processing snapshot data...');
        print('[NearSync]   My position: ${_lastPosition!.latitude}, ${_lastPosition!.longitude}');
        print('[NearSync]   My userId: $_currentUserId');
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        print('[NearSync]   Total users in database: ${data.length}');
        
        for (final entry in data.entries) {
          print('[NearSync]   --- Checking user: ${entry.key}');
          
          if (entry.key == _currentUserId) {
            print('[NearSync]   ⏭️ Skipping: This is myself');
            continue;
          }
          
          final userData = Map<String, dynamic>.from(entry.value as Map);
          final userName = userData['name'] ?? 'Unknown';
          
          // Check if user is still online (updated recently)
          final lastUpdated = userData['lastUpdated'] as int? ?? 0;
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final ageMinutes = (nowMs - lastUpdated) / 60000;
          final lastUpdatedDate = DateTime.fromMillisecondsSinceEpoch(lastUpdated);
          
          print('[NearSync]   User: $userName');
          print('[NearSync]   Last updated: $lastUpdatedDate (${ageMinutes.toStringAsFixed(1)} min ago)');
          print('[NearSync]   Threshold: $offlineThresholdMinutes min');
          
          if (lastUpdated < cutoffTime) {
            print('[NearSync]   ⏭️ Skipping: User is stale (${ageMinutes.toStringAsFixed(1)} min > $offlineThresholdMinutes min)');
            continue;
          }
          
          print('[NearSync]   ✅ User is online (${ageMinutes.toStringAsFixed(1)} min < $offlineThresholdMinutes min)');
          
          final userLat = (userData['latitude'] as num?)?.toDouble();
          final userLng = (userData['longitude'] as num?)?.toDouble();
          
          if (userLat == null || userLng == null) {
            print('[NearSync]   ⏭️ Skipping: Missing coordinates');
            continue;
          }
          
          print('[NearSync]   User position: $userLat, $userLng');
          
          // Calculate distance
          final distanceMeters = Geolocator.distanceBetween(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            userLat,
            userLng,
          );
          
          final distanceKm = distanceMeters / 1000;
          print('[NearSync]   Distance: ${distanceKm.toStringAsFixed(2)} km (radius: $radiusKm km)');
          
          // Only include users within radius
          if (distanceKm <= radiusKm) {
            print('[NearSync]   ✅ INCLUDED: Within radius!');
            nearbyUsers.add(NearbyUser(
              userId: userData['userId'] as String? ?? entry.key,
              walletAddress: userData['walletAddress'] as String? ?? '',
              name: userData['name'] as String? ?? 'Anonymous',
              profilePicture: userData['profilePicture'] as String?,
              distanceKm: distanceKm,
              lastSeen: DateTime.fromMillisecondsSinceEpoch(lastUpdated),
            ));
          } else {
            print('[NearSync]   ⏭️ Skipping: Too far (${distanceKm.toStringAsFixed(2)} km > $radiusKm km)');
          }
        }
      }
    } catch (e) {
      print('[NearSync] ❌ Error fetching nearby users: $e');
      print('[NearSync]   Error type: ${e.runtimeType}');
      if (e is FirebaseException) {
        print('[NearSync]   Firebase error code: ${e.code}');
        print('[NearSync]   Firebase error message: ${e.message}');
      }
    }

    // Sort by distance
    nearbyUsers.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    
    print('[NearSync] ✅ Found ${nearbyUsers.length} nearby users');
    for (var user in nearbyUsers) {
      print('[NearSync]   - ${user.name} (${user.formattedDistance})');
    }
    
    return nearbyUsers;
  }

  /// Add a user to contacts in Firestore
  Future<bool> addToContacts(NearbyUser user) async {
    if (_currentUserId == null) return false;

    try {
      await _firestore
          .collection('users')
          .doc(_currentUserId)
          .collection('contacts')
          .doc(user.userId)
          .set({
        'userId': user.userId,
        'walletAddress': user.walletAddress,
        'name': user.name,
        'profilePicture': user.profilePicture,
        'addedAt': FieldValue.serverTimestamp(),
        'addedVia': 'near_sync',
      });
      return true;
    } catch (e) {
      print('[NearSync] Error adding contact: $e');
      return false;
    }
  }

  /// Check if a user is already in contacts
  Future<bool> isInContacts(String userId) async {
    if (_currentUserId == null) return false;

    try {
      final doc = await _firestore
          .collection('users')
          .doc(_currentUserId)
          .collection('contacts')
          .doc(userId)
          .get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  /// Get user's saved contacts
  Future<List<NearbyUser>> getContacts() async {
    if (_currentUserId == null) return [];

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(_currentUserId)
          .collection('contacts')
          .orderBy('addedAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return NearbyUser(
          userId: data['userId'] as String? ?? doc.id,
          walletAddress: data['walletAddress'] as String? ?? '',
          name: data['name'] as String? ?? 'Unknown',
          profilePicture: data['profilePicture'] as String?,
          distanceKm: 0,
          lastSeen: (data['addedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        );
      }).toList();
    } catch (e) {
      print('[NearSync] Error fetching contacts: $e');
      return [];
    }
  }

  /// Dispose resources
  void dispose() {
    disable();
  }
}

/// Model for nearby user data
class NearbyUser {
  final String userId;
  final String walletAddress;
  final String name;
  final String? profilePicture;
  final double distanceKm;
  final DateTime lastSeen;

  NearbyUser({
    required this.userId,
    required this.walletAddress,
    required this.name,
    this.profilePicture,
    required this.distanceKm,
    required this.lastSeen,
  });

  String get formattedDistance {
    if (distanceKm < 1) {
      return '${(distanceKm * 1000).round()} m';
    }
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  String get shortAddress {
    if (walletAddress.length > 12) {
      return '${walletAddress.substring(0, 6)}...${walletAddress.substring(walletAddress.length - 4)}';
    }
    return walletAddress;
  }
}
