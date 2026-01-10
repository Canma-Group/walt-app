import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification_model.dart';

class NotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Collection reference
  CollectionReference get _notificationsRef => _db.collection('notifications');

  /// Create a new notification
  Future<NotificationModel> createNotification({
    required String userId,
    required NotificationType type,
    required String title,
    required String body,
    String? imageUrl,
    Map<String, dynamic>? data,
  }) async {
    try {
      final docRef = _notificationsRef.doc();
      final now = DateTime.now();

      final notification = NotificationModel(
        id: docRef.id,
        userId: userId.toLowerCase(),
        type: type,
        title: title,
        body: body,
        imageUrl: imageUrl,
        isRead: false,
        createdAt: now,
        data: data,
      );

      await docRef.set(notification.toJson());
      print('[NotificationService] Created notification: ${docRef.id} for user: $userId');

      // TODO: Trigger push notification via FCM here
      // await _sendPushNotification(userId, title, body, data);

      return notification;
    } catch (e) {
      print('[NotificationService] Error creating notification: $e');
      rethrow;
    }
  }

  /// Get all notifications for a user
  Future<List<NotificationModel>> getNotifications({
    required String userId,
    int limit = 50,
    bool unreadOnly = false,
  }) async {
    try {
      final normalizedUserId = userId.toLowerCase();
      print('[NotificationService] Getting notifications for: $normalizedUserId');

      QuerySnapshot snapshot;
      
      try {
        // Try with orderBy (requires composite index)
        Query query = _notificationsRef
            .where('user_id', isEqualTo: normalizedUserId)
            .orderBy('created_at', descending: true);

        if (unreadOnly) {
          query = query.where('is_read', isEqualTo: false);
        }

        snapshot = await query.limit(limit).get();
      } catch (indexError) {
        // Fallback: query without orderBy if index not ready
        print('[NotificationService] Index not ready, using fallback query: $indexError');
        Query query = _notificationsRef
            .where('user_id', isEqualTo: normalizedUserId);

        if (unreadOnly) {
          query = query.where('is_read', isEqualTo: false);
        }

        snapshot = await query.limit(limit).get();
      }
      
      print('[NotificationService] Found ${snapshot.docs.length} notifications');

      final notifications = snapshot.docs.map((doc) {
        return NotificationModel.fromJson(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
      }).toList();
      
      // Sort in memory if we used fallback query
      notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      return notifications;
    } catch (e) {
      print('[NotificationService] Error getting notifications: $e');
      return [];
    }
  }

  /// Get unread notification count
  Future<int> getUnreadCount(String userId) async {
    try {
      final normalizedUserId = userId.toLowerCase();

      final snapshot = await _notificationsRef
          .where('user_id', isEqualTo: normalizedUserId)
          .where('is_read', isEqualTo: false)
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e) {
      print('[NotificationService] Error getting unread count: $e');
      return 0;
    }
  }

  /// Mark a notification as read
  Future<void> markAsRead(String notificationId) async {
    try {
      await _notificationsRef.doc(notificationId).update({
        'is_read': true,
        'read_at': FieldValue.serverTimestamp(),
      });
      print('[NotificationService] Marked notification $notificationId as read');
    } catch (e) {
      print('[NotificationService] Error marking as read: $e');
    }
  }

  /// Mark all notifications as read for a user
  Future<void> markAllAsRead(String userId) async {
    try {
      final normalizedUserId = userId.toLowerCase();

      final snapshot = await _notificationsRef
          .where('user_id', isEqualTo: normalizedUserId)
          .where('is_read', isEqualTo: false)
          .get();

      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {
          'is_read': true,
          'read_at': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      print('[NotificationService] Marked ${snapshot.docs.length} notifications as read');
    } catch (e) {
      print('[NotificationService] Error marking all as read: $e');
    }
  }

  /// Delete a notification
  Future<void> deleteNotification(String notificationId) async {
    try {
      await _notificationsRef.doc(notificationId).delete();
      print('[NotificationService] Deleted notification $notificationId');
    } catch (e) {
      print('[NotificationService] Error deleting notification: $e');
    }
  }

  /// Delete all notifications for a user
  Future<void> deleteAllNotifications(String userId) async {
    try {
      final normalizedUserId = userId.toLowerCase();

      final snapshot = await _notificationsRef
          .where('user_id', isEqualTo: normalizedUserId)
          .get();

      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      print('[NotificationService] Deleted ${snapshot.docs.length} notifications');
    } catch (e) {
      print('[NotificationService] Error deleting all notifications: $e');
    }
  }

  /// Stream of notifications for real-time updates
  Stream<List<NotificationModel>> notificationsStream(String userId) {
    final normalizedUserId = userId.toLowerCase();

    return _notificationsRef
        .where('user_id', isEqualTo: normalizedUserId)
        .orderBy('created_at', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return NotificationModel.fromJson(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
      }).toList();
    });
  }

  /// Stream of unread count for real-time badge updates
  Stream<int> unreadCountStream(String userId) {
    final normalizedUserId = userId.toLowerCase();

    return _notificationsRef
        .where('user_id', isEqualTo: normalizedUserId)
        .where('is_read', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }
}
