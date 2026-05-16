import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? verificationId;

  // 🔥 SAFE USER SAVE (FIXED)
  Future<void> _saveUserToFirestore(User user) async {
    final String? email = user.email;
    final String? phone = user.phoneNumber;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'uid': user.uid,

      // ✅ FIX: prevent empty string
      'email': (email != null && email.isNotEmpty) ? email : null,

      // 📲 phone users supported
      'phone': phone,

      'trustedUsers': [],
      'sharing': false,
    }, SetOptions(merge: true));
  }

  // 📲 Send OTP
  Future<void> sendOTP(String phone) async {
    Completer<void> completer = Completer();

    await _auth.verifyPhoneNumber(
      phoneNumber: phone,

      verificationCompleted: (PhoneAuthCredential credential) async {
        final userCred = await _auth.signInWithCredential(credential);
        await _saveUserToFirestore(userCred.user!);

        if (!completer.isCompleted) completer.complete();
      },

      verificationFailed: (FirebaseAuthException e) {
        if (!completer.isCompleted) completer.completeError(e);
      },

      codeSent: (String vId, int? resendToken) {
        verificationId = vId;
        if (!completer.isCompleted) completer.complete();
      },

      codeAutoRetrievalTimeout: (String vId) {
        verificationId = vId;
      },
    );

    return completer.future;
  }

  // 🔐 Verify OTP
  Future<UserCredential> verifyOTP(String otp) async {
    PhoneAuthCredential credential = PhoneAuthProvider.credential(
      verificationId: verificationId!,
      smsCode: otp,
    );

    final userCred = await _auth.signInWithCredential(credential);
    await _saveUserToFirestore(userCred.user!);

    return userCred;
  }

  // 🔐 Email login
  Future<UserCredential> signInWithEmailPassword(
    String email,
    String password,
  ) async {
    final userCred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    await _saveUserToFirestore(userCred.user!);
    return userCred;
  }

  // 🆕 Register email
  Future<UserCredential> createUserWithEmailPassword(
    String email,
    String password,
  ) async {
    final userCred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    await _saveUserToFirestore(userCred.user!);
    return userCred;
  }

  // 📲 Normalize phone
  String normalizePhone(String input) {
    final digitsOnly = input.replaceAll(RegExp(r'\D'), '');

    if (digitsOnly.startsWith('09') && digitsOnly.length == 11) {
      return '+63${digitsOnly.substring(1)}';
    }

    if (digitsOnly.startsWith('9') && digitsOnly.length == 10) {
      return '+63$digitsOnly';
    }

    if (digitsOnly.startsWith('63') && digitsOnly.length == 12) {
      return '+$digitsOnly';
    }

    return input;
  }
}
