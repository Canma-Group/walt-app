import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddQuickContactSheet extends StatefulWidget {
  final Function(Map<String, dynamic>) onContactAdded;
  
  const AddQuickContactSheet({Key? key, required this.onContactAdded}) : super(key: key);
  
  @override
  State<AddQuickContactSheet> createState() => _AddQuickContactSheetState();
}

class _AddQuickContactSheetState extends State<AddQuickContactSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    
    setState(() => _isSearching = true);
    
    try {
      final queryLower = query.toLowerCase();
      final results = <Map<String, dynamic>>[];
      final seenIds = <String>{};
      
      // Get all users and filter client-side (simpler approach for small datasets)
      final allUsers = await FirebaseFirestore.instance
          .collection('users')
          .limit(50)
          .get();
      
      for (final doc in allUsers.docs) {
        final data = doc.data();
        final name = (data['name'] as String? ?? '').toLowerCase();
        final walletAddr = doc.id.toLowerCase();
        
        // Match by name or wallet address
        if (name.contains(queryLower) || walletAddr.contains(queryLower)) {
          if (!seenIds.contains(doc.id)) {
            seenIds.add(doc.id);
            results.add({
              'wallet_address': doc.id,
              'name': data['name'] ?? 'Unknown',
              'photo_url': data['profile_photo_url'],
            });
          }
        }
      }
      
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      print('[AddQuickContact] Search error: $e');
      if (mounted) setState(() => _isSearching = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Add Quick Contact',
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => _searchUsers(value),
              decoration: InputDecoration(
                hintText: 'Search by name or wallet address...',
                hintStyle: GoogleFonts.poppins(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                    ? Center(
                        child: Text(
                          _searchController.text.isEmpty ? 'Search for users to add' : 'No users found',
                          style: GoogleFonts.poppins(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final user = _searchResults[index];
                          final name = user['name'] as String;
                          final walletAddr = user['wallet_address'] as String;
                          final photoUrl = user['photo_url'] as String?;
                          
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF4B7BF5),
                              backgroundImage: photoUrl != null && photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                              child: photoUrl == null || photoUrl.isEmpty
                                  ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white))
                                  : null,
                            ),
                            title: Text(name, style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                            subtitle: Text(
                              '${walletAddr.substring(0, 6)}...${walletAddr.substring(walletAddr.length - 4)}',
                              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.add_circle, color: Color(0xFF4B7BF5)),
                              onPressed: () {
                                widget.onContactAdded(user);
                                Navigator.pop(context);
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
