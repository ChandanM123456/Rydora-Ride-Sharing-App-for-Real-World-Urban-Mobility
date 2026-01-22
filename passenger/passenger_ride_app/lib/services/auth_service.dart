import 'package:firebase_auth/firebase_auth.dart';

// Service class to handle all Firebase Authentication operations
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Sign up with email and password
  Future<User?> signUp(String email, String password) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      return result.user; // Return the created user object
    } catch (e) {
      // Print any errors that occur during sign-up
      print('Error signing up: ${e.toString()}');
      return null;
    }
  }

  // Sign in with email and password
  Future<User?> signIn(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      return result.user; // Return the logged-in user object
    } catch (e) {
      // Print any errors that occur during sign-in
      print('Error signing in: ${e.toString()}');
      return null;
    }
  }

  // Sign out the current user
  Future<void> signOut() async {
    try {
      return await _auth.signOut();
    } catch (e) {
      // Print any errors that occur during sign-out
      print('Error signing out: ${e.toString()}');
      rethrow; // Re-throw the error for the UI to handle if needed
    }
  }

  // Get the currently authenticated user
  User? getCurrentUser() {
    return _auth.currentUser;
  }

  // Stream to listen to authentication state changes (e.g., login/logout)
  Stream<User?> get user {
    return _auth.authStateChanges();
  }
}
