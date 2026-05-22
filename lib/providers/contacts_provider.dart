import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/member_model.dart';
import '../services/firestore_service.dart';

/// Real-time stream of the current user's saved contacts.
final userContactsProvider = StreamProvider<List<MemberModel>>((ref) {
  return FirestoreService.instance.userContactsStream();
});

