import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../services/near_sync_service.dart';
import 'transfer_details_page.dart';

class NearSyncPage extends StatefulWidget {
  const NearSyncPage({Key? key}) : super(key: key);

  @override
  State<NearSyncPage> createState() => _NearSyncPageState();
}

class _NearSyncPageState extends State<NearSyncPage> with SingleTickerProviderStateMixin {
  final _nearSyncService = NearSyncService();
  
  bool _isLoading = false;
  bool _isSyncEnabled = false;
  bool _isRefreshing = false;
  String? _errorMessage;
  List<NearbyUser> _nearbyUsers = [];
  double _radiusKm = 5.0;
  int _radiusIndex = 1; // 0=3km, 1=5km, 2=200km (shown as >10km)
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initializeService();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeService() async {
    print('[NearSyncPage] 🔧 Initializing Near Sync service...');
    final authState = context.read<AuthBloc>().state;
    print('[NearSyncPage] Auth state: ${authState.runtimeType}');
    
    String? userId;
    String? walletAddress;

    if (authState is AuthSuccess) {
      userId = authState.user.id;
      walletAddress = authState.user.walletAddress;
      print('[NearSyncPage] AuthSuccess - userId: $userId, wallet: $walletAddress');
    } else if (authState is AuthNeedsWalletVerification) {
      userId = authState.user.id;
      walletAddress = authState.user.walletAddress;
      print('[NearSyncPage] AuthNeedsWalletVerification - userId: $userId, wallet: $walletAddress');
    } else {
      print('[NearSyncPage] ⚠️ Unexpected auth state: $authState');
    }

    if (userId != null && walletAddress != null) {
      await _nearSyncService.initialize(
        userId: userId,
        walletAddress: walletAddress,
      );
      print('[NearSyncPage] ✅ Service initialized');
    } else {
      print('[NearSyncPage] ❌ Cannot initialize - missing userId or walletAddress');
    }
  }

  Future<void> _toggleSync() async {
    // Prevent multiple simultaneous toggle calls
    if (_isLoading) {
      print('[NearSyncPage] ⏳ Already loading, ignoring toggle');
      return;
    }
    
    print('[NearSyncPage] 🔄 Toggle sync called, current state: $_isSyncEnabled');
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isSyncEnabled) {
        print('[NearSyncPage] Disabling Near Sync...');
        await _nearSyncService.disable();
        _refreshTimer?.cancel();
        _pulseController.stop();
        setState(() {
          _isSyncEnabled = false;
          _nearbyUsers = [];
        });
        print('[NearSyncPage] ✅ Near Sync disabled');
      } else {
        print('[NearSyncPage] Enabling Near Sync...');
        final success = await _nearSyncService.enable();
        print('[NearSyncPage] Enable result: $success');
        if (success) {
          _pulseController.repeat(reverse: true);
          setState(() => _isSyncEnabled = true);
          print('[NearSyncPage] Refreshing nearby users...');
          await _refreshNearbyUsers();
          _startAutoRefresh();
          print('[NearSyncPage] ✅ Near Sync enabled successfully');
        } else {
          print('[NearSyncPage] ❌ Failed to enable Near Sync');
          setState(() {
            _errorMessage = 'Failed to enable Near Sync. Please check location permissions.';
          });
        }
      }
    } catch (e) {
      print('[NearSyncPage] ❌ Error in toggleSync: $e');
      print('[NearSyncPage] Stack trace: ${StackTrace.current}');
      setState(() {
        _errorMessage = 'Error: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshNearbyUsers(),
    );
  }

  Future<void> _refreshNearbyUsers() async {
    if (!_isSyncEnabled) {
      print('[NearSyncPage] ⚠️ Refresh skipped - sync not enabled');
      return;
    }
    
    print('[NearSyncPage] 🔄 Refreshing nearby users (radius: $_radiusKm km)...');
    setState(() => _isRefreshing = true);
    
    try {
      final users = await _nearSyncService.getNearbyUsers(radiusKm: _radiusKm);
      print('[NearSyncPage] ✅ Received ${users.length} nearby users');
      if (mounted) {
        setState(() {
          _nearbyUsers = users;
          _errorMessage = null;
        });
      }
    } catch (e) {
      print('[NearSyncPage] ❌ Error fetching nearby users: $e');
      if (mounted) {
        setState(() => _errorMessage = 'Failed to fetch nearby users: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _addToContacts(NearbyUser user) async {
    print('[NearSyncPage] 📇 Adding ${user.name} to contacts...');
    try {
      final success = await _nearSyncService.addToContacts(user);
      if (success) {
        print('[NearSyncPage] ✅ Contact added successfully');
        _showSnackBar('${user.name} added to contacts!', Colors.green);
      } else {
        print('[NearSyncPage] ❌ Failed to add contact');
        _showSnackBar('Failed to add contact', Colors.red);
      }
    } catch (e) {
      print('[NearSyncPage] ❌ Error adding contact: $e');
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  void _showUserProfile(NearbyUser user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFFFFFFF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _buildUserProfileSheet(ctx, user),
    );
  }

  void _navigateToTransfer(NearbyUser user) {
    Navigator.pop(context); // Close bottom sheet
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransferDetailsPage(
          recipientId: user.userId,
          recipientName: user.name,
          recipientWalletAddress: user.walletAddress,
          recipientProfilePhoto: user.profilePicture,
          isInternalUser: true,
        ),
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1264EF),
        title: Text(
          'Near Sync',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isSyncEnabled && !_isRefreshing)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _refreshNearbyUsers,
            ),
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildSyncToggle(),
          if (_errorMessage != null) _buildErrorBanner(),
          if (_isSyncEnabled) _buildRadiusSlider(),
          Expanded(
            child: _isSyncEnabled ? _buildNearbyUsersList() : _buildDisabledState(),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncToggle() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isSyncEnabled
              ? [const Color(0xFF1264EF), const Color(0xFF0A3989)]
              : [const Color(0xFFE8EEF6), const Color(0xFFD0DCE8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: _isSyncEnabled
            ? [
                BoxShadow(
                  color: const Color(0xFF1264EF).withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _isSyncEnabled ? _pulseAnimation.value : 1.0,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: _isSyncEnabled
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isSyncEnabled ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isSyncEnabled ? 'Near Sync Active' : 'Near Sync Off',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isSyncEnabled
                      ? 'Finding wallet users nearby...'
                      : 'Enable to discover nearby users',
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          _isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Switch(
                  value: _isSyncEnabled,
                  onChanged: (_) => _toggleSync(),
                  activeColor: Colors.white,
                  activeTrackColor: Colors.white24,
                ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.poppins(color: Colors.red, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadiusSlider() {
    // Map index to actual radius: 0=3km, 1=5km, 2=2000km (shown as >10km)
    final radiusValues = [3.0, 5.0, 2000.0];
    final radiusLabels = ['3 km', '5 km', 'Lebih dari 10 km'];
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Search Radius',
                style: GoogleFonts.poppins(
                  color: const Color(0xFF3A3A3A),
                  fontSize: 14,
                ),
              ),
              Text(
                radiusLabels[_radiusIndex],
                style: GoogleFonts.poppins(
                  color: const Color(0xFF1264EF),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Slider(
            value: _radiusIndex.toDouble(),
            min: 0,
            max: 2,
            divisions: 2,
            activeColor: const Color(0xFF1264EF),
            inactiveColor: Colors.grey.shade300,
            onChanged: (value) {
              setState(() {
                _radiusIndex = value.toInt();
                _radiusKm = radiusValues[_radiusIndex];
              });
            },
            onChangeEnd: (_) => _refreshNearbyUsers(),
          ),
          // Labels below slider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: radiusLabels.map((label) => Text(
                label,
                style: GoogleFonts.poppins(
                  color: Colors.white38,
                  fontSize: 10,
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisabledState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.location_off,
              size: 60,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Near Sync is disabled',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Enable Near Sync to discover other wallet users nearby and add them to your contacts.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.white54,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _toggleSync,
            icon: const Icon(Icons.wifi_tethering),
            label: const Text('Enable Near Sync'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1264EF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNearbyUsersList() {
    return Column(
      children: [
        // Radar View
        Expanded(
          flex: 2,
          child: _buildRadarView(),
        ),
        // User List
        if (_nearbyUsers.isNotEmpty)
          Expanded(
            flex: 1,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _nearbyUsers.length,
              itemBuilder: (context, index) {
                final user = _nearbyUsers[index];
                return _buildUserCard(user);
              },
            ),
          ),
        if (_nearbyUsers.isEmpty)
          Expanded(
            flex: 1,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isRefreshing)
                    const CircularProgressIndicator(color: Color(0xFF08BFC1))
                  else
                    Text(
                      'Scanning for nearby users...',
                      style: GoogleFonts.poppins(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Radius: ${_radiusKm.toStringAsFixed(1)} km',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF1264EF),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRadarView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight) * 0.85;
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Radar circles
                ...List.generate(4, (index) {
                  final circleSize = size * (0.25 + (index * 0.25));
                  return Container(
                    width: circleSize,
                    height: circleSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF1264EF).withValues(alpha: 0.2 + (index * 0.1)),
                        width: 1,
                      ),
                    ),
                  );
                }),
                // Radar sweep animation
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _pulseController.value * 2 * math.pi,
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            colors: [
                              Colors.transparent,
                              const Color(0xFF1264EF).withValues(alpha: 0.3),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.25, 0.5],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // Center dot (You)
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1264EF),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1264EF).withValues(alpha: 0.5),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                // "You" label
                Positioned(
                  bottom: size / 2 - 30,
                  child: Text(
                    'You',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF1264EF),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Nearby users as dots
                ..._buildUserDots(size),
                // Distance labels
                Positioned(
                  right: size / 2 + 5,
                  top: size / 2 - 10,
                  child: Text(
                    '${(_radiusKm / 4).toStringAsFixed(1)}km',
                    style: GoogleFonts.poppins(
                      color: Colors.white30,
                      fontSize: 8,
                    ),
                  ),
                ),
                Positioned(
                  right: size / 4 + 5,
                  top: size / 2 - 10,
                  child: Text(
                    '${(_radiusKm / 2).toStringAsFixed(1)}km',
                    style: GoogleFonts.poppins(
                      color: Colors.white30,
                      fontSize: 8,
                    ),
                  ),
                ),
                Positioned(
                  right: 5,
                  top: size / 2 - 10,
                  child: Text(
                    '${_radiusKm.toStringAsFixed(1)}km',
                    style: GoogleFonts.poppins(
                      color: Colors.white30,
                      fontSize: 8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildUserDots(double radarSize) {
    final List<Widget> dots = [];
    final random = math.Random(42); // Fixed seed for consistent positions
    
    for (int i = 0; i < _nearbyUsers.length; i++) {
      final user = _nearbyUsers[i];
      // Calculate position based on distance
      final distanceRatio = (user.distanceKm / _radiusKm).clamp(0.1, 0.95);
      final radius = (radarSize / 2) * distanceRatio;
      
      // Use random angle for demo (in real app, use actual bearing)
      final angle = random.nextDouble() * 2 * math.pi;
      final x = radius * math.cos(angle);
      final y = radius * math.sin(angle);
      
      dots.add(
        Positioned(
          left: radarSize / 2 + x - 12,
          top: radarSize / 2 + y - 12,
          child: GestureDetector(
            onTap: () => _showUserProfile(user),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    
    return dots;
  }

  Widget _buildUserCard(NearbyUser user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showUserProfile(user),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildAvatar(user),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.shortAddress,
                        style: GoogleFonts.robotoMono(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1264EF).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        user.formattedDistance,
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF1264EF),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Icon(
                      Icons.chevron_right,
                      color: Colors.white54,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(NearbyUser user) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFF1264EF).withValues(alpha: 0.2),
        shape: BoxShape.circle,
        image: user.profilePicture != null
            ? DecorationImage(
                image: NetworkImage(user.profilePicture!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: user.profilePicture == null
          ? Center(
              child: Text(
                user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                style: GoogleFonts.poppins(
                  color: const Color(0xFF1264EF),
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildUserProfileSheet(BuildContext ctx, NearbyUser user) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          _buildAvatar(user),
          const SizedBox(height: 16),
          Text(
            user.name,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: user.walletAddress));
              _showSnackBar('Address copied!', const Color(0xFF1264EF));
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  user.shortAddress,
                  style: GoogleFonts.robotoMono(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.copy, color: Colors.white54, size: 16),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${user.formattedDistance} away',
            style: GoogleFonts.poppins(
              color: const Color(0xFF1264EF),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.person_add,
                  label: 'Add Contact',
                  color: const Color(0xFF1264EF),
                  onTap: () {
                    Navigator.pop(ctx);
                    _addToContacts(user);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.send,
                  label: 'Transfer',
                  color: Colors.green,
                  onTap: () => _navigateToTransfer(user),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.poppins(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
