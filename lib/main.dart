import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'debug_agent_log.dart';
import 'services/location_tracking_service.dart';
import 'services/permission_service.dart';
import 'widgets/location_permission_instruction_video.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initBackgroundService();
  await Firebase.initializeApp();
  
  // Set system UI overlay style to prevent full screen
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  
  // Ensure the app doesn't go into full screen mode
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
    overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
  );
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FoodnPals',
      home: const RootScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  String? _token;
  String? _email;
  String? _initialUrl;
  bool _loading = true;
  bool _hasSeenWelcome = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _checkWelcomeAndLogin();
  }

  Future<void> _checkWelcomeAndLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenWelcome = prefs.getBool('hasSeenWelcome') ?? false;
    final token = prefs.getString('ManualToken');
    final email = prefs.getString('UserEmail');
    
    setState(() {
      _hasSeenWelcome = hasSeenWelcome;
      _loading = false;
    });
    
    if (token != null && email != null && token.isNotEmpty && email.isNotEmpty) {
      setState(() {
        _token = token;
        _email = email;
        _initialUrl = 'https://foodnpals.com/MobileLogin.php?email=${Uri.encodeComponent(email)}&token=${Uri.encodeComponent(token)}';
      });
    } else {
      setState(() {
        _token = null;
        _email = null;
        _initialUrl = null;
      });
    }
  }

  void _onLogin(String token, String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ManualToken', token);
    await prefs.setString('UserEmail', email);
    setState(() {
      _token = token;
      _email = email;
      _initialUrl = 'https://foodnpals.com/MobileLogin.php?email=${Uri.encodeComponent(email)}&token=${Uri.encodeComponent(token)}';
    });
  }

  void _onWelcomeComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenWelcome', true);
    setState(() {
      _hasSeenWelcome = true;
    });
  }

  void _onLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ManualToken');
    await prefs.remove('UserEmail');
    setState(() {
      _token = null;
      _email = null;
      _initialUrl = null;
    });
  }

  Future<void> _requestPermissions() async {
    // Request notification permission
    var notifStatus = await Permission.notification.status;
    if (!notifStatus.isGranted) {
      await Permission.notification.request();
    }
    
    // Request location permission
    var locStatus = await Permission.location.status;
    if (!locStatus.isGranted) {
      await Permission.location.request();
    }
    
    // Request storage permission for file browsing (profile picture upload)
    var storageStatus = await Permission.storage.status;
    if (!storageStatus.isGranted) {
      await Permission.storage.request();
    }
    
    // Request photos permission for accessing photos (profile picture upload)
    var photosStatus = await Permission.photos.status;
    if (!photosStatus.isGranted) {
      await Permission.photos.request();
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    // Show welcome screen for first-time users
    if (!_hasSeenWelcome) {
      return WelcomeScreen(onWelcomeComplete: _onWelcomeComplete);
    }
    
    // Show login screen if not logged in
    if (_token == null || _email == null) {
      return LoginScreen(onLogin: _onLogin);
    }

    // Show main app if logged in
    return WebViewScreen(
      email: _email!,
      token: _token!,
      onLogout: _onLogout,
      initialUrl: _initialUrl!,
    );
  }
}

String generateRandomToken([int length = 16]) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final rand = Random.secure();
  return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
}

class WelcomeScreen extends StatelessWidget {
  final VoidCallback onWelcomeComplete;
  
  const WelcomeScreen({super.key, required this.onWelcomeComplete});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background image covering top 40% of screen (same as login)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.40,
            child: Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/loginImg.png'),
                  fit: BoxFit.cover,
                ),
              ),
              // Overlay gradient for better text visibility
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.1),
                      Colors.black.withOpacity(0.1),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Main content
          SafeArea(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom,
                ),
                child: Column(
                  children: [
                    // Top section (empty space for background image)
                    SizedBox(
                      width: double.infinity,
                      height: MediaQuery.of(context).size.height * 0.3,
                    ),
                    // Bottom section with welcome content
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(30),
                          topRight: Radius.circular(30),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(30),
                        child: Column(
                          children: [
                            const SizedBox(height: 30),
                            
                            // Welcome title
                            const Text(
                              'Welcome to FoodnPals',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            
                            const SizedBox(height: 20),
                            
                            // Welcome subtitle
                            const Text(
                              'Your ultimate restaurant booking and food ordering companion. Book tables instantly and order food on your way, so it\'s ready when you arrive.',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.black54,
                                height: 1.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            
                            const SizedBox(height: 40),
                            
                            // Get Started button
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: () {
                                  // Navigate to WebView with HomeMobile.php
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (context) => WebViewScreen(
                                        email: 'guest',
                                        token: 'guest',
                                        onLogout: () {},
                                        initialUrl: 'https://foodnpals.com/HomeMobile.php',
                                      ),
                                    ),
                                  );
                                  onWelcomeComplete();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4CBB17),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'Get Started',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 20),
                            
                            // Sign in button (smaller, positioned bottom right)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {
                                  // Navigate to login screen
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (context) => LoginScreen(
                                        onLogin: (token, email) {
                                          // Handle login and navigate to main app
                                          Navigator.of(context).pushReplacement(
                                            MaterialPageRoute(
                                              builder: (context) => WebViewScreen(
                                                email: email,
                                                token: token,
                                                onLogout: () {},
                                                initialUrl: 'https://foodnpals.com/MobileLogin.php?email=${Uri.encodeComponent(email)}&token=${Uri.encodeComponent(token)}',
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  );
                                  onWelcomeComplete();
                                },
                                child: const Text(
                                  'Sign in now',
                                  style: TextStyle(
                                    color: Color(0xFF4CBB17),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  final void Function(String token, String email) onLogin;
  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailController.text = '';
    _passwordController.text = '';
  }

  Future<void> _login() async {
    if (!_loginFormKey.currentState!.validate()) return;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final token = generateRandomToken();
      
      print('Attempting login with email: $email'); // Debug print
      
      // 1. Call login_api.php
      final response = await http.post(
        Uri.parse('https://foodnpals.com/login_api.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': email,
          'password': password,
          'token': token,
        }),
      );
      
      print('Response status: ${response.statusCode}'); // Debug print
      print('Response body: ${response.body}'); // Debug print
      
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Parsed response: $data'); // Debug print
        if (data['success'] == true) {
          print('Login successful, calling onLogin'); // Debug print
          widget.onLogin(token, email);
        } else {
          if (!mounted) return;
          setState(() {
            _error = data['message'] ?? 'Login failed. Please check your credentials.';
          });
        }
      } else {
        if (!mounted) return;
        setState(() {
          _error = 'Login failed. HTTP Status: ${response.statusCode}';
        });
      }
    } catch (e) {
      print('Login error: $e'); // Debug print
      if (!mounted) return;
      setState(() {
        _error = 'An error occurred: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Simple GoogleSignIn constructor for version 6.3.0
      final GoogleSignIn googleSignIn = GoogleSignIn();
      
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() { _loading = false; });
        return;
      }
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;
      if (user != null && user.email != null) {
        final token = generateRandomToken();
        final email = user.email!;

        final response = await http.post(
          Uri.parse('https://foodnpals.com/auth.php'),
          body: {
            'action': 'google_signin',
            'email': email,
            'token': token,
          },
        );

        if (mounted && response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            widget.onLogin(token, email);
          } else {
            setState(() { _error = data['message'] ?? 'Google sign-in failed on server.'; });
          }
        } else {
          setState(() { _error = 'Google sign-in failed. HTTP Status: ${response.statusCode}'; });
        }
      } else {
        setState(() { _error = 'Google sign-in failed.'; });
      }
    } catch (e) {
      setState(() { _error = 'Google sign-in error: \n$e'; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF50B849), // Green background for bottom section
      body: Stack(
        children: [
          // Background image covering top 40% of screen
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.40,
            child: Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/loginImg.png'),
                  fit: BoxFit.cover,
                ),
              ),
              // Overlay gradient for better text visibility
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.1),
                      Colors.black.withOpacity(0.1),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Main content
          SafeArea(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom,
                ),
                child: Column(
                  children: [
                    // Top section (empty space for background image)
                    SizedBox(
                      width: double.infinity,
                      height: MediaQuery.of(context).size.height * 0.3,
                    ),
                    // Bottom section with login form
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(30),
                          topRight: Radius.circular(30),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(30),
                        child: Column(
                          children: [
                            // Tab selector
                            const SizedBox(height: 30),
                            
                            // Login form
                            Form(
                              key: _loginFormKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Email field
                                  const Text(
                                    'Email',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _emailController,
                                    decoration: InputDecoration(
                                      hintText: 'Example@email.com',
                                      hintStyle: TextStyle(color: Colors.grey[400]),
                                      filled: true,
                                      fillColor: Colors.grey[50],
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 16,
                                      ),
                                    ),
                                    keyboardType: TextInputType.emailAddress,
                                    validator: (value) => value == null || value.isEmpty ? 'Enter email' : null,
                                  ),
                                  
                                  const SizedBox(height: 20),
                                  
                                  // Password field
                                  const Text(
                                    'Password',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _passwordController,
                                    decoration: InputDecoration(
                                      hintText: 'At least 8 characters',
                                      hintStyle: TextStyle(color: Colors.grey[400]),
                                      filled: true,
                                      fillColor: Colors.grey[50],
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 16,
                                      ),
                                    ),
                                    obscureText: true,
                                    validator: (value) => value == null || value.isEmpty ? 'Enter password' : null,
                                  ),
                                  
                                  const SizedBox(height: 12),
                                  
                                  // Forgot password
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) => const ForgotPasswordWebViewScreen(),
                                          ),
                                        );
                                      },
                                      child: const Text(
                                        'Forgot Password?',
                                        style: TextStyle(
                                          color: Color(0xFF4CBB17),
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  
                                  const SizedBox(height: 20),
                                  
                                  // Error message
                                  if (_error != null) ...[
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                                      ),
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(color: Colors.red, fontSize: 14),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                  ],
                                  
                                  // Login button
                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: ElevatedButton(
                                      onPressed: _loading ? null : _login,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF4CBB17),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(25),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: _loading
                                          ? const SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                              ),
                                            )
                                          : const Text(
                                              'Login',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                    ),
                                  ),
                                  
                                  const SizedBox(height: 20),
                                  
                                  // Or divider
                                  Row(
                                    children: [
                                      Expanded(child: Divider(color: Colors.grey[300])),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 16),
                                        child: Text(
                                          'Or',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      Expanded(child: Divider(color: Colors.grey[300])),
                                    ],
                                  ),
                                  
                                  const SizedBox(height: 20),
                                  
                                  // Google login button
                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: OutlinedButton.icon(
                                      onPressed: _loading ? null : _signInWithGoogle,
                                      icon: Image.asset('assets/images/google_logo.png', height: 20),
                                      label: const Text(
                                        'Continue with Google',
                                        style: TextStyle(
                                          color: Colors.black87,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        side: BorderSide(color: Colors.grey[300]!),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(25),
                                        ),
                                      ),
                                    ),
                                  ),
                                  
                                  const SizedBox(height: 40),
                                  
                                  // Sign up link
                                  Center(
                                    child: GestureDetector(
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) => const SignUpWebViewScreen(),
                                          ),
                                        );
                                      },
                                      child: RichText(
                                        text: TextSpan(
                                          text: "Don't you have an account? ",
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 14,
                                          ),
                                          children: [
                                            TextSpan(
                                              text: 'Sign up',
                                              style: const TextStyle(
                                                color: Color(0xFF4CBB17),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SignUpWebViewScreen extends StatefulWidget {
  const SignUpWebViewScreen({super.key});

  @override
  State<SignUpWebViewScreen> createState() => _SignUpWebViewScreenState();
}

class _SignUpWebViewScreenState extends State<SignUpWebViewScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) async {
          final url = request.url;
          final lowerUrl = url.toLowerCase();
          
          if (lowerUrl.contains('login.html') || lowerUrl.contains('logout.php')) {
            Navigator.of(context).pop(); // Go back to login screen
            return NavigationDecision.prevent;
          }
          
          if (url.startsWith('tel:')) {
            await launchUrl(Uri.parse(url));
            return NavigationDecision.prevent;
          }
          
          // Handle map links and Android intent URLs - launch externally
          if (url.startsWith('https://maps.google.com/') || 
              url.startsWith('https://www.google.com/maps/') ||
              url.startsWith('geo:') || 
              url.startsWith('google.navigation:') || 
              url.startsWith('waze:') ||
              url.startsWith('intent://') ||
              url.contains('maps.google.com') ||
              url.contains('google.com/maps')) {
            try {
              if (url.startsWith('intent://')) {
                // Handle Android intent URLs for Google Maps
                final uri = Uri.parse(url);
                final scheme = uri.queryParameters['scheme'];
                final package = uri.queryParameters['package'];
                final data = uri.queryParameters['S.browser_fallback_url'];
                
                if (scheme == 'https' && package == 'com.google.android.apps.maps') {
                  // Extract coordinates and construct Google Maps URL
                  final urlMatch = RegExp(r'/(\d+\.?\d*),(\d+\.?\d*)').firstMatch(url);
                  if (urlMatch != null) {
                    final lat = urlMatch.group(1);
                    final lng = urlMatch.group(2);
                    final mapsUrl = 'https://www.google.com/maps/dir/$lat,$lng';
                    if (await canLaunchUrl(Uri.parse(mapsUrl))) {
                      await launchUrl(Uri.parse(mapsUrl));
                    }
                  } else if (data != null && await canLaunchUrl(Uri.parse(data))) {
                    await launchUrl(Uri.parse(data));
                  }
                } else if (await canLaunchUrl(Uri.parse(url))) {
                  await launchUrl(Uri.parse(url));
                }
              } else if (await canLaunchUrl(Uri.parse(url))) {
                await launchUrl(Uri.parse(url));
              }
            } catch (e) {
              print('Error launching URL: $e');
            }
            return NavigationDecision.prevent;
          }
          
          return NavigationDecision.navigate;
        },
        onWebResourceError: (error) async {
          // Log the error details for debugging
          print('SignUp WebView Error Details:');
          print('- URL: ${error.url}');
          print('- Error Type: ${error.errorType}');
          print('- Error Code: ${error.errorCode}');
          print('- Description: ${error.description}');
          
          // Show offline page for any network or loading errors
          // await _showSignUpOfflinePage();
        },
        onHttpError: (error) async {
          // Handle HTTP errors (404, 403, 500, etc.)
          print('SignUp HTTP Error: ${error.response?.statusCode} for ${error.request?.uri}');
          
          // Show offline page for HTTP errors
          // await _showSignUpOfflinePage();
        },
      ))
      ..loadRequest(Uri.parse('https://foodnpals.com/SignUp.php'));
  }

  // ignore: unused_element
  Future<void> _showSignUpOfflinePage() async {
    try {
      // Load bundled offline page from assets
      final html = await DefaultAssetBundle.of(context).loadString('android_asset/offline.html');
      await _controller.loadHtmlString(html);
    } catch (e) {
      print('Error loading offline page: $e');
      // Fallback: show a simple error message
      await _controller.loadHtmlString('''
        <html>
          <body style="font-family: Arial; text-align: center; padding: 50px; background: #f8f9fa;">
            <h1 style="color: #4CBB17;">FoodnPals</h1>
            <h2>Connection Issue</h2>
            <p>Please check your internet connection and try again.</p>
            <button onclick="window.location.reload();" style="background: #4CBB17; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer;">Retry</button>
          </body>
        </html>
      ''');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign Up'),
        backgroundColor: const Color(0xFF4CBB17),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}

class ForgotPasswordWebViewScreen extends StatefulWidget {
  const ForgotPasswordWebViewScreen({super.key});

  @override
  State<ForgotPasswordWebViewScreen> createState() => _ForgotPasswordWebViewScreenState();
}

class _ForgotPasswordWebViewScreenState extends State<ForgotPasswordWebViewScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) async {
          final url = request.url;
          final lowerUrl = url.toLowerCase();
          
          if (lowerUrl.contains('login.html')) {
            Navigator.of(context).pop(); // Go back to login screen
            return NavigationDecision.prevent;
          }
          
          if (url.startsWith('tel:')) {
            await launchUrl(Uri.parse(url));
            return NavigationDecision.prevent;
          }
          
          // Handle map links and Android intent URLs - launch externally
          if (url.startsWith('https://maps.google.com/') || 
              url.startsWith('https://www.google.com/maps/') ||
              url.startsWith('geo:') || 
              url.startsWith('google.navigation:') || 
              url.startsWith('waze:') ||
              url.startsWith('intent://') ||
              url.contains('maps.google.com') ||
              url.contains('google.com/maps')) {
            try {
              if (url.startsWith('intent://')) {
                // Handle Android intent URLs for Google Maps
                final uri = Uri.parse(url);
                final scheme = uri.queryParameters['scheme'];
                final package = uri.queryParameters['package'];
                final data = uri.queryParameters['S.browser_fallback_url'];
                
                if (scheme == 'https' && package == 'com.google.android.apps.maps') {
                  // Extract coordinates and construct Google Maps URL
                  final urlMatch = RegExp(r'/(\d+\.?\d*),(\d+\.?\d*)').firstMatch(url);
                  if (urlMatch != null) {
                    final lat = urlMatch.group(1);
                    final lng = urlMatch.group(2);
                    final mapsUrl = 'https://www.google.com/maps/dir/$lat,$lng';
                    if (await canLaunchUrl(Uri.parse(mapsUrl))) {
                      await launchUrl(Uri.parse(mapsUrl));
                    }
                  } else if (data != null && await canLaunchUrl(Uri.parse(data))) {
                    await launchUrl(Uri.parse(data));
                  }
                } else if (await canLaunchUrl(Uri.parse(url))) {
                  await launchUrl(Uri.parse(url));
                }
              } else if (await canLaunchUrl(Uri.parse(url))) {
                await launchUrl(Uri.parse(url));
              }
            } catch (e) {
              print('Error launching URL: $e');
            }
            return NavigationDecision.prevent;
          }
          
          return NavigationDecision.navigate;
        },
        onWebResourceError: (error) async {
          // Log the error details for debugging
          print('ForgotPassword WebView Error Details:');
          print('- URL: ${error.url}');
          print('- Error Type: ${error.errorType}');
          print('- Error Code: ${error.errorCode}');
          print('- Description: ${error.description}');
          
          // Show offline page for any network or loading errors
          // await _showOfflinePage();
        },
        onHttpError: (error) async {
          // Handle HTTP errors (404, 403, 500, etc.)
          print('ForgotPassword HTTP Error: ${error.response?.statusCode} for ${error.request?.uri}');
          
          // Show offline page for HTTP errors
          // await _showOfflinePage();
        },
      ))
      ..loadRequest(Uri.parse('https://foodnpals.com/ForgetPswd.php'));
  }

  // ignore: unused_element
  Future<void> _showOfflinePage() async {
    try {
      // Load bundled offline page from assets
      final html = await DefaultAssetBundle.of(context).loadString('android_asset/offline.html');
      await _controller.loadHtmlString(html);
    } catch (e) {
      print('Error loading offline page: $e');
      // Fallback: show a simple error message
      await _controller.loadHtmlString('''
        <html>
          <body style="font-family: Arial; text-align: center; padding: 50px; background: #f8f9fa;">
            <h1 style="color: #4CBB17;">FoodnPals</h1>
            <h2>Connection Issue</h2>
            <p>Please check your internet connection and try again.</p>
            <button onclick="window.location.reload();" style="background: #4CBB17; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer;">Retry</button>
          </body>
        </html>
      ''');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Forgot Password'),
        backgroundColor: const Color(0xFF4CBB17),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  final String email;
  final String token;
  final String initialUrl;
  final VoidCallback? onLogout;
  const WebViewScreen({super.key, required this.email, required this.token, this.onLogout, required this.initialUrl});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> with WidgetsBindingObserver {
  late final WebViewController _controller;
  final _urlController = TextEditingController();
  int _selectedIndex = 0;
  StreamSubscription<Position>? _positionStream;
  Timer? _locationTimer;
  Timer? _pageLoadTimer;
  bool _isLoading = true;
  bool _pageFinished = false;
  late final DateTime _screenShownAt;
  
  // Connection error handling
  int _retryCount = 0;
  static const int _maxRetries = 3;
  Timer? _retryTimer;
  String? _lastFailedUrl;

  /// Avoid duplicate foreground starts when confirmation page reloads.
  final Set<String> _autoTrackedReservationIds = <String>{};

  /// Blocks interaction with the WebView on [payment_setup.php] until location is "always" (Android) or acceptable (iOS).
  bool _paymentSetupLocationBlocked = false;

  static const String _kHomeMobileUrl = 'https://foodnpals.com/HomeMobile.php';

  late final List<String> _urls;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _screenShownAt = DateTime.now();
    
    // Initialize URLs (authentication will be handled via cookies)
    _urls = [
      _kHomeMobileUrl, // Home
      'https://foodnpals.com/CustomerBookings.php', // Booking
      'https://foodnpals.com/CustomerOrders.php', // Orders
      'https://foodnpals.com/CustomerProfile.php', // Profile
    ];
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36')
      ..enableZoom(true)
      ..addJavaScriptChannel(
        'FpStartTracking',
        onMessageReceived: _onFpStartTrackingMessage,
      )
      ..addJavaScriptChannel(
        'FpStopTracking',
        onMessageReceived: _onFpStopTrackingMessage,
      )
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) async {
          final url = request.url;
          final lowerUrl = url.toLowerCase();
          
          // Only show loading overlay and timeout for main frame navigations.
          // Sub-frame navigations (Stripe payment iframes, embedded widgets)
          // must NOT trigger loading — onPageFinished won't fire for them,
          // so the overlay would stay forever and the timeout would show offline page.
          if (request.isMainFrame) {
            _pageFinished = false;
            if (mounted) {
              setState(() {
                _isLoading = true;
              });
            }
            
            // Set a timeout for page loading (30 seconds — generous for mobile networks)
            _pageLoadTimer?.cancel();
            _pageLoadTimer = Timer(const Duration(seconds: 30), () {
              if (mounted && _isLoading) {
                print('Page load timeout - attempting to retry');
                _handleConnectionError(url, 'Page load timeout');
              }
            });
          }
          
          // Handle map links and Android intent URLs - launch externally
          if (url.startsWith('https://maps.google.com/') || 
              url.startsWith('https://www.google.com/maps/') ||
              url.startsWith('geo:') || 
              url.startsWith('google.navigation:') || 
              url.startsWith('waze:') ||
              url.startsWith('intent://') ||
              url.contains('maps.google.com') ||
              url.contains('google.com/maps')) {
            try {
              print('Detected map URL: $url');
              
              if (url.startsWith('intent://')) {
                // Handle Android intent URLs for Google Maps
                final uri = Uri.parse(url);
                final scheme = uri.queryParameters['scheme'];
                final package = uri.queryParameters['package'];
                final data = uri.queryParameters['S.browser_fallback_url'];
                
                print('Intent URL - scheme: $scheme, package: $package, data: $data');
                
                if (scheme == 'https' && package == 'com.google.android.apps.maps') {
                  // Try to launch Google Maps app directly
                  final mapsAppUrl = 'google.navigation:q=${uri.host}${uri.path}';
                  try {
                    await launchUrl(Uri.parse(mapsAppUrl));
                    print('Launched Google Maps app with navigation');
                  } catch (e) {
                    print('Failed to launch Google Maps app: $e');
                    if (data != null) {
                      try {
                        await launchUrl(Uri.parse(data));
                        print('Launched fallback URL: $data');
                      } catch (e2) {
                        print('Failed to launch fallback URL: $e2');
                      }
                    }
                  }
                } else if (data != null) {
                  try {
                    await launchUrl(Uri.parse(data));
                    print('Launched data URL: $data');
                  } catch (e) {
                    print('Failed to launch data URL: $e');
                  }
                }
              } else if (url.startsWith('geo:')) {
                // Handle geo: URLs
                print('Launching geo URL: $url');
                try {
                  await launchUrl(Uri.parse(url));
                } catch (e) {
                  print('Failed to launch geo URL: $e');
                }
              } else if (url.startsWith('google.navigation:')) {
                // Handle Google Navigation URLs
                print('Launching Google Navigation: $url');
                try {
                  await launchUrl(Uri.parse(url));
                } catch (e) {
                  print('Failed to launch Google Navigation: $e');
                }
              } else if (url.startsWith('waze:')) {
                // Handle Waze URLs
                print('Launching Waze: $url');
                try {
                  await launchUrl(Uri.parse(url));
                } catch (e) {
                  print('Failed to launch Waze: $e');
                }
              } else if (url.contains('maps.google.com') || url.contains('google.com/maps')) {
                // Handle Google Maps web URLs - convert to app URLs
                print('Converting Google Maps web URL to app URL: $url');
                
                // Extract coordinates from various Google Maps URL formats
                String? lat, lng, address;
                
                // Try to extract coordinates from @lat,lng format
                final coordMatch = RegExp(r'@(-?\d+\.?\d*),(-?\d+\.?\d*)').firstMatch(url);
                if (coordMatch != null) {
                  lat = coordMatch.group(1);
                  lng = coordMatch.group(2);
                }
                
                // Try to extract coordinates from /dir/lat,lng/lat,lng format
                final dirMatch = RegExp(r'/dir/(-?\d+\.?\d*),(-?\d+\.?\d*)/(-?\d+\.?\d*),(-?\d+\.?\d*)').firstMatch(url);
                if (dirMatch != null) {
                  // For directions, use the destination coordinates
                  lat = dirMatch.group(3);
                  lng = dirMatch.group(4);
                  print('Extracted destination coordinates: $lat, $lng');
                }
                
                // Try to extract coordinates from /place/lat,lng format
                final placeMatch = RegExp(r'/place/[^/]+/(-?\d+\.?\d*),(-?\d+\.?\d*)').firstMatch(url);
                if (placeMatch != null) {
                  lat = placeMatch.group(1);
                  lng = placeMatch.group(2);
                }
                
                // Try to extract coordinates from query parameters
                final uri = Uri.parse(url);
                lat ??= uri.queryParameters['ll']?.split(',')[0];
                lng ??= uri.queryParameters['ll']?.split(',')[1];
                
                // Try to extract address
                address = uri.queryParameters['q'];
                
                if (lat != null && lng != null) {
                  // Launch with coordinates
                  final mapsUrl = 'google.navigation:q=$lat,$lng';
                  print('Launching Google Maps with coordinates: $mapsUrl');
                  try {
                    await launchUrl(Uri.parse(mapsUrl));
                    print('Successfully launched Google Maps with coordinates');
                  } catch (e) {
                    print('Failed to launch Google Maps with coordinates: $e');
                    // Fallback to geo URL
                    final geoUrl = 'geo:$lat,$lng';
                    print('Fallback to geo URL: $geoUrl');
                    try {
                      await launchUrl(Uri.parse(geoUrl));
                      print('Successfully launched geo URL');
                    } catch (e2) {
                      print('Failed to launch geo URL: $e2');
                      // Try with different format
                      final mapsWebUrl = 'https://maps.google.com/maps?q=$lat,$lng';
                      print('Final fallback to web URL: $mapsWebUrl');
                      try {
                        await launchUrl(Uri.parse(mapsWebUrl));
                        print('Successfully launched web URL');
                      } catch (e3) {
                        print('All launch attempts failed: $e3');
                      }
                    }
                  }
                } else if (address != null) {
                  // Launch with address
                  final mapsUrl = 'google.navigation:q=${Uri.encodeComponent(address)}';
                  print('Launching Google Maps with address: $mapsUrl');
                  try {
                    await launchUrl(Uri.parse(mapsUrl));
                    print('Successfully launched Google Maps with address');
                  } catch (e) {
                    print('Failed to launch Google Maps with address: $e');
                  }
                } else {
                  // Fallback to original URL
                  print('Fallback: launching original URL: $url');
                  try {
                    await launchUrl(Uri.parse(url));
                    print('Successfully launched original URL');
                  } catch (e) {
                    print('Failed to launch original URL: $e');
                  }
                }
              } else {
                // Generic URL launch
                print('Launching generic URL: $url');
                try {
                  await launchUrl(Uri.parse(url));
                  print('Successfully launched generic URL');
                } catch (e) {
                  print('Failed to launch generic URL: $e');
                }
              }
            } catch (e) {
              print('Error launching map URL: $e');
            }
            return NavigationDecision.prevent;
          }

          // Rewrite Profile.php to ProfileMobile.php for mobile app
          if (url.contains('/Profile.php')) {
            final newUrl = url.replaceAll('/Profile.php', '/ProfileMobile.php');
            _controller.loadRequest(Uri.parse(newUrl));
            return NavigationDecision.prevent;
          }
          // Rewrite Home.php to HomeMobile.php for mobile app
          if (url.contains('Home.php')) {
            final newUrl = url.replaceAll('Home.php', 'HomeMobile.php');
            _controller.loadRequest(Uri.parse(newUrl));
            return NavigationDecision.prevent;
          }
          if (lowerUrl.contains('login.html') || lowerUrl.contains('logout.php')) {
            if (widget.onLogout != null) {
              widget.onLogout!();
            }
            return NavigationDecision.prevent;
          }
          if (url.startsWith('tel:')) {
            await launchUrl(Uri.parse(url));
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onUrlChange: (change) {
          if (!mounted) return;
          print('URL Changed to: ${change.url}'); // Debug print
          unawaited(_reevaluatePaymentSetupLocationGate(change.url));
        },
        onPageStarted: (url) {
          if (!mounted) return;
          print('Page Started loading: $url');
          // Inject geolocation override immediately when page starts loading
          _injectRobustGeolocationOverride();
        },
        onPageFinished: (url) {
          if (!mounted) return;
          print('Page Finished loading: $url');
          _urlController.text = url;
          
          _pageLoadTimer?.cancel();
          _resetRetryCounter();
          _reinjectGeolocationOverride();
          unawaited(_injectLocationTrackingBridge());
          unawaited(_reevaluatePaymentSetupLocationGate(url));
          unawaited(_maybeAutoStartTrackingFromConfirmationUrl(url));
          _startLocationUpdates();
          
          _dismissLoadingOverlay();
        },
        onWebResourceError: (error) async {
          // Log the error details for debugging
          print('WebView Error Details:');
          print('- URL: ${error.url}');
          print('- Error Type: ${error.errorType}');
          print('- Error Code: ${error.errorCode}');
          print('- Description: ${error.description}');
          print('- Is Main Frame: ${error.isForMainFrame}');
          
          // ONLY handle main frame errors — ignore sub-resource failures.
          // Sub-resource errors (failed images, analytics scripts, Stripe JS,
          // ad pixels, CDN resources) are completely normal and should never
          // show the offline page.
          if (error.isForMainFrame != true) {
            print('Ignoring sub-resource error for: ${error.url}');
            return;
          }
          
          // Main frame connection/network error — retry with backoff, then offline page
          await _handleConnectionError(error.url ?? '', error.description);
        },
        onHttpError: (error) async {
          // Log HTTP errors but do NOT show offline page.
          // onHttpError fires for ALL resources (images, scripts, Stripe JS,
          // analytics pixels, fonts). A sub-resource 404 is completely normal.
          // Real connection failures are caught by onWebResourceError instead.
          print('HTTP Error: ${error.response?.statusCode} for ${error.request?.uri}');
        },
      ));

    if (_controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (_controller.platform as AndroidWebViewController)
          .setOnPlatformPermissionRequest((request) {
        print('Permission requested: ${request.types}');
        // Grant all permission requests including geolocation
        request.grant();
      });
      
      // Additional Android WebView configuration for geolocation
      (_controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
      
      // Set additional Android WebView settings for better geolocation support
      (_controller.platform as AndroidWebViewController)
          .setOnShowFileSelector((params) async {
            return [];
          });
    }
    
    // Configure iOS WebView for geolocation
    if (_controller.platform is WebKitWebViewController) {
      (_controller.platform as WebKitWebViewController)
          .setOnPlatformPermissionRequest((request) {
        print('iOS Permission requested: ${request.types}');
        // Grant all permission requests including geolocation
        request.grant();
      });
    }
    
    _controller.loadRequest(Uri.parse(widget.initialUrl));
    
   // _requestLocationAndSync();
   // _startLocationSync();
  }

  /// Hides the loading overlay only after:
  ///  1. A minimum of 2 seconds since the screen appeared (avoids a jarring flash).
  ///  2. An extra 800 ms after onPageFinished so CSS/images/JS finish painting.
  Future<void> _dismissLoadingOverlay() async {
    _pageFinished = true;

    final elapsed = DateTime.now().difference(_screenShownAt);
    final minDuration = const Duration(seconds: 2);

    if (elapsed < minDuration) {
      await Future.delayed(minDuration - elapsed);
    }

    // Give the WebView an extra moment to paint after the HTML is "finished"
    await Future.delayed(const Duration(milliseconds: 800));

    if (mounted && _pageFinished) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel();
    _locationTimer?.cancel();
    _pageLoadTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reevaluatePaymentSetupLocationGate());
      unawaited(_recoverWebViewIfBrokenOnResume());
    }
  }

  bool _isFoodnpalsPaymentSetupUrl(String? url) {
    if (url == null || url.isEmpty) {
      return false;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }
    if (!uri.host.toLowerCase().contains('foodnpals.com')) {
      return false;
    }
    return uri.path.toLowerCase().contains('payment_setup.php');
  }

  bool _isFoodnpalsConfirmationUrl(String? url) {
    if (url == null || url.isEmpty) {
      return false;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }
    if (!uri.host.toLowerCase().contains('foodnpals.com')) {
      return false;
    }
    return uri.path.toLowerCase().contains('confirmation.php');
  }

  /// After lock/unlock or failed back navigation, WebView may show a system error page on Confirmation or Payment setup — send user home.
  Future<void> _recoverWebViewIfBrokenOnResume() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) {
      return;
    }
    final url = await _controller.currentUrl() ?? _urlController.text;
    final recoverHere =
        _isFoodnpalsConfirmationUrl(url) || _isFoodnpalsPaymentSetupUrl(url);
    if (!recoverHere) {
      return;
    }
    try {
      final Object? raw = await _controller.runJavaScriptReturningResult(
        '(function(){ try { var t = document.documentElement ? document.documentElement.innerText : ""; return t.length > 1400 ? t.substring(0, 1400) : t; } catch(e) { return ""; } })();',
      );
      final text = raw?.toString().toLowerCase() ?? '';
      if (text.contains('not available') ||
          text.contains('could not be loaded') ||
          text.contains('couldn\'t be loaded') ||
          text.contains('couldn\'t load') ||
          text.contains('net::err') ||
          text.contains('err_cache_miss') ||
          text.contains('webpage not available') ||
          text.contains('no internet') ||
          text.contains('connection was reset') ||
          text.contains('err_connection')) {
        await _navigateWebViewToHome();
      }
    } catch (_) {
      // WebView may not be ready for JS yet
    }
  }

  Future<void> _reevaluatePaymentSetupLocationGate([String? url]) async {
    if (!mounted) {
      return;
    }
    if (widget.token == 'guest' || widget.email == 'guest') {
      if (_paymentSetupLocationBlocked) {
        setState(() => _paymentSetupLocationBlocked = false);
      }
      return;
    }
    final current = url ?? await _controller.currentUrl() ?? _urlController.text;
    if (!_isFoodnpalsPaymentSetupUrl(current)) {
      if (_paymentSetupLocationBlocked) {
        setState(() => _paymentSetupLocationBlocked = false);
      }
      return;
    }
    var ok = await PermissionService.hasRequiredLocationForJourneyTracking();
    if (!ok) {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
        ok = await PermissionService.hasRequiredLocationForJourneyTracking();
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _paymentSetupLocationBlocked = !ok;
    });
  }

  /// When the site does not call [window.startTracking], start from confirmation URL + API coords.
  Future<void> _maybeAutoStartTrackingFromConfirmationUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    if (!uri.host.toLowerCase().contains('foodnpals.com')) {
      return;
    }
    if (!uri.path.toLowerCase().contains('confirmation.php')) {
      return;
    }
    final id = uri.queryParameters['ID'] ?? uri.queryParameters['id'];
    if (id == null || id.isEmpty) {
      return;
    }
    if (_autoTrackedReservationIds.contains(id)) {
      return;
    }
    if (widget.token == 'guest' || widget.email == 'guest') {
      return;
    }

    // #region agent log
    agentDebugLog(
      hypothesisId: 'H1_auto',
      location: 'main.dart:_maybeAutoStartTrackingFromConfirmationUrl',
      message: 'confirmation_url_detected',
      data: <String, Object?>{'reservationId': id},
    );
    // #endregion agent log

    if (!mounted) {
      return;
    }
    final granted = await PermissionService.hasRequiredLocationForJourneyTracking();
    // #region agent log
    agentDebugLog(
      hypothesisId: 'H3',
      location: 'main.dart:_maybeAutoStartTrackingFromConfirmationUrl',
      message: 'auto_location_permission_result',
      data: <String, Object?>{'granted': granted},
    );
    // #endregion agent log
    if (!mounted || !granted) {
      return;
    }

    // Retry: first GET can be 403 if DB status is not Pending/Accepted yet (race on confirmation load).
    var ok = false;
    for (var attempt = 0; attempt < 6; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted) {
          return;
        }
      }
      // #region agent log
      agentDebugLog(
        hypothesisId: 'H2',
        location: 'main.dart:_maybeAutoStartTrackingFromConfirmationUrl',
        message: 'auto_start_attempt',
        data: <String, Object?>{'attempt': attempt},
      );
      // #endregion agent log
      ok = await startReservationTrackingUsingFetchedMeta(
        reservationId: id,
        bearerToken: widget.token,
      );
      if (ok) {
        break;
      }
    }
    // #region agent log
    agentDebugLog(
      hypothesisId: 'H1_auto',
      location: 'main.dart:_maybeAutoStartTrackingFromConfirmationUrl',
      message: 'auto_startReservationTrackingUsingFetchedMeta_done',
      data: <String, Object?>{'ok': ok},
    );
    // #endregion agent log
    if (ok) {
      _autoTrackedReservationIds.add(id);
    }
  }

  void _onFpStartTrackingMessage(JavaScriptMessage message) {
    unawaited(_handleFpStartTracking(message.message));
  }

  void _onFpStopTrackingMessage(JavaScriptMessage message) {
    stopReservationTracking();
  }

  Future<void> _injectLocationTrackingBridge() async {
    try {
      await _controller.runJavaScript(r'''
(function() {
  window.startTracking = function(bookingId, restaurantLat, restaurantLng) {
    try {
      FpStartTracking.postMessage(JSON.stringify({
        bookingId: String(bookingId),
        restaurantLat: Number(restaurantLat),
        restaurantLng: Number(restaurantLng)
      }));
    } catch (e) { console.error(e); }
  };
  window.stopTracking = function() {
    try { FpStopTracking.postMessage('{}'); } catch (e) { console.error(e); }
  };
})();
''');
    } catch (e) {
      print('Inject location tracking bridge failed: $e');
    }
  }

  Future<void> _handleFpStartTracking(String raw) async {
    // #region agent log
    agentDebugLog(
      hypothesisId: 'H1',
      location: 'main.dart:_handleFpStartTracking',
      message: 'js_channel_message_received',
      data: <String, Object?>{'rawLen': raw.length},
    );
    // #endregion agent log
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // #region agent log
      agentDebugLog(
        hypothesisId: 'H1',
        location: 'main.dart:_handleFpStartTracking',
        message: 'json_parse_failed',
        data: const <String, Object?>{},
      );
      // #endregion agent log
      return;
    }
    final id = data['bookingId']?.toString() ?? data['reservationId']?.toString();
    final lat = (data['restaurantLat'] as num?)?.toDouble();
    final lng = (data['restaurantLng'] as num?)?.toDouble();
    if (id == null || lat == null || lng == null) {
      // #region agent log
      agentDebugLog(
        hypothesisId: 'H1',
        location: 'main.dart:_handleFpStartTracking',
        message: 'missing_booking_or_coords',
        data: <String, Object?>{
          'hasId': id != null,
          'hasLat': lat != null,
          'hasLng': lng != null,
        },
      );
      // #endregion agent log
      return;
    }

    if (!mounted) return;
    final granted = await PermissionService.hasRequiredLocationForJourneyTracking();
    // #region agent log
    agentDebugLog(
      hypothesisId: 'H3',
      location: 'main.dart:_handleFpStartTracking',
      message: 'location_permission_result',
      data: <String, Object?>{'granted': granted},
    );
    // #endregion agent log
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location set to "Allow all the time" is required to track your journey. '
            'Enable it in Settings (complete payment setup first if you see that screen).',
          ),
        ),
      );
      return;
    }

    final ok = await startReservationTracking(
      reservationId: id,
      restaurantLat: lat,
      restaurantLng: lng,
      bearerToken: widget.token,
    );
    // #region agent log
    agentDebugLog(
      hypothesisId: 'H2_H4',
      location: 'main.dart:_handleFpStartTracking',
      message: 'startReservationTracking_done',
      data: <String, Object?>{'ok': ok},
    );
    // #endregion agent log
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not start journey tracking. It is only available when the reservation is Pending or Accepted.',
          ),
        ),
      );
    }
  }

  // Robust geolocation injection that works consistently
  Future<void> _injectRobustGeolocationOverride() async {
    try {
      print('Starting robust geolocation injection...');
      
      // Get current location with retry mechanism
      Position? position;
      int attempts = 0;
      const maxAttempts = 3;
      
      while (position == null && attempts < maxAttempts) {
        attempts++;
        try {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 5),
          );
          print('Location obtained successfully on attempt $attempts');
        } catch (e) {
          print('Location attempt $attempts failed: $e');
          if (attempts < maxAttempts) {
            await Future.delayed(Duration(milliseconds: 500 * attempts));
          }
        }
      }
      
      // If we still don't have location, use default coordinates
      if (position == null) {
        print('Using default location coordinates');
        position = Position(
          latitude: 0.0,
          longitude: 0.0,
          timestamp: DateTime.now(),
          accuracy: 100.0,
          altitude: 0.0,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );
      }
      
      final lat = position.latitude;
      final lng = position.longitude;
      final accuracy = position.accuracy;
      final timestamp = position.timestamp.millisecondsSinceEpoch;
      
      await _controller.runJavaScript('''
        console.log('Injecting robust geolocation override...');
        
        // Store location globally immediately
        window.nativeLocation = {
          latitude: $lat,
          longitude: $lng,
          accuracy: $accuracy,
          altitude: ${position.altitude},
          speed: ${position.speed},
          heading: ${position.heading},
          timestamp: $timestamp
        };
        
        console.log('Native location stored:', window.nativeLocation);
        
        // Completely override navigator.geolocation before any website code runs
        if (navigator.geolocation) {
          console.log('Overriding geolocation API with robust implementation');
          
          // Override getCurrentPosition with immediate response
          navigator.geolocation.getCurrentPosition = function(success, error, options) {
            console.log('getCurrentPosition called - returning native location immediately');
            
            const mockPosition = {
              coords: {
                latitude: window.nativeLocation.latitude,
                longitude: window.nativeLocation.longitude,
                accuracy: window.nativeLocation.accuracy,
                altitude: window.nativeLocation.altitude,
                altitudeAccuracy: null,
                heading: window.nativeLocation.heading,
                speed: window.nativeLocation.speed
              },
              timestamp: window.nativeLocation.timestamp
            };
            
            console.log('Returning location:', mockPosition.coords.latitude, mockPosition.coords.longitude);
            
            if (success) {
              // Use immediate callback to avoid timing issues
              success(mockPosition);
            }
          };
          
          // Override watchPosition
          navigator.geolocation.watchPosition = function(success, error, options) {
            console.log('watchPosition called - using native location');
            
            const mockPosition = {
              coords: {
                latitude: window.nativeLocation.latitude,
                longitude: window.nativeLocation.longitude,
                accuracy: window.nativeLocation.accuracy,
                altitude: window.nativeLocation.altitude,
                altitudeAccuracy: null,
                heading: window.nativeLocation.heading,
                speed: window.nativeLocation.speed
              },
              timestamp: window.nativeLocation.timestamp
            };
            
            if (success) {
              success(mockPosition);
            }
            
            return 1; // Mock watch ID
          };
          
          // Override clearWatch
          navigator.geolocation.clearWatch = function(watchId) {
            console.log('clearWatch called for:', watchId);
          };
        }
        
        // Override permissions API to always return granted
        if (!navigator.permissions) {
          navigator.permissions = {};
        }
        
        navigator.permissions.query = function(descriptor) {
          console.log('Permission query for:', descriptor.name);
          return Promise.resolve({
            state: 'granted',
            onchange: null
          });
        };
        
        // Test the override immediately
        if (navigator.geolocation) {
          navigator.geolocation.getCurrentPosition(
            function(position) {
              console.log('✅ Geolocation test successful:', position.coords.latitude, position.coords.longitude);
            },
            function(error) {
              console.log('❌ Geolocation test failed:', error.code, error.message);
            },
            {
              enableHighAccuracy: true,
              timeout: 1000,
              maximumAge: 0
            }
          );
        }
        
        console.log('✅ Robust geolocation override complete');
      ''');
      
      print('Robust geolocation injection completed successfully');
    } catch (e) {
      print('Error in robust geolocation injection: $e');
    }
  }

  // Reinject geolocation after page finishes loading to ensure it's still active
  Future<void> _reinjectGeolocationOverride() async {
    try {
      print('Reinjecting geolocation override after page load...');
      
      // Wait a bit for the page to fully load
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Check if geolocation is still working
      await _controller.runJavaScript('''
        if (window.nativeLocation && navigator.geolocation) {
          console.log('Reinjecting geolocation override...');
          
          // Re-override getCurrentPosition to ensure it's still working
          navigator.geolocation.getCurrentPosition = function(success, error, options) {
            console.log('getCurrentPosition called (reinjected) - returning native location');
            
            const mockPosition = {
              coords: {
                latitude: window.nativeLocation.latitude,
                longitude: window.nativeLocation.longitude,
                accuracy: window.nativeLocation.accuracy,
                altitude: window.nativeLocation.altitude,
                altitudeAccuracy: null,
                heading: window.nativeLocation.heading,
                speed: window.nativeLocation.speed
              },
              timestamp: window.nativeLocation.timestamp
            };
            
            if (success) {
              success(mockPosition);
            }
          };
          
          // Test again
          navigator.geolocation.getCurrentPosition(
            function(position) {
              console.log('✅ Reinjection test successful:', position.coords.latitude, position.coords.longitude);
            },
            function(error) {
              console.log('❌ Reinjection test failed:', error.code, error.message);
            },
            { enableHighAccuracy: true, timeout: 1000, maximumAge: 0 }
          );
          
          console.log('✅ Geolocation reinjection complete');
        } else {
          console.log('❌ Cannot reinject - native location or geolocation not available');
        }
      ''');
    } catch (e) {
      print('Error during geolocation reinjection: $e');
    }
  }


  // Start periodic location updates
  void _startLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        
        await _controller.runJavaScript('''
          // Update the stored location data and re-override if needed
          if (window.nativeLocation) {
            window.nativeLocation.latitude = ${position.latitude};
            window.nativeLocation.longitude = ${position.longitude};
            window.nativeLocation.accuracy = ${position.accuracy};
            window.nativeLocation.timestamp = ${position.timestamp.millisecondsSinceEpoch};
            console.log('Location updated:', ${position.latitude}, ${position.longitude});
            
            // Re-override getCurrentPosition to ensure it uses the updated location
            if (navigator.geolocation) {
              navigator.geolocation.getCurrentPosition = function(success, error, options) {
                console.log('getCurrentPosition called (updated) - returning current location');
                
                const mockPosition = {
                  coords: {
                    latitude: window.nativeLocation.latitude,
                    longitude: window.nativeLocation.longitude,
                    accuracy: window.nativeLocation.accuracy,
                    altitude: window.nativeLocation.altitude,
                    altitudeAccuracy: null,
                    heading: window.nativeLocation.heading,
                    speed: window.nativeLocation.speed
                  },
                  timestamp: window.nativeLocation.timestamp
                };
                
                if (success) {
                  success(mockPosition);
                }
              };
            }
          }
        ''');
      } catch (e) {
        print('Error updating location: $e');
      }
    });
  }

  // Handle connection errors with automatic retry
  Future<void> _handleConnectionError(String url, String errorDescription) async {
    print('Connection error detected: $errorDescription for URL: $url');

    if (_isFoodnpalsConfirmationUrl(url) || _isFoodnpalsPaymentSetupUrl(url)) {
      _resetRetryCounter();
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      await _navigateWebViewToHome();
      return;
    }

    // Store the failed URL for retry
    _lastFailedUrl = url;
    
    // Check if we should retry or show offline page
    if (_retryCount < _maxRetries) {
      _retryCount++;
      
      // Calculate retry delay with exponential backoff (1s, 2s, 4s)
      final retryDelay = Duration(seconds: _retryCount);
      
      print('Retrying connection in ${retryDelay.inSeconds} seconds (attempt $_retryCount/$_maxRetries)');
      
      // Show loading indicator
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      }
      
      // Schedule retry
      _retryTimer?.cancel();
      _retryTimer = Timer(retryDelay, () async {
        if (mounted && _lastFailedUrl != null) {
          print('Attempting to reload URL: $_lastFailedUrl');
          try {
            await _controller.loadRequest(Uri.parse(_lastFailedUrl!));
          } catch (e) {
            print('Error during retry: $e');
            // If retry fails, try again or show offline page
            await _handleConnectionError(_lastFailedUrl!, 'Retry failed: $e');
          }
        }
      });
    } else {
      // Max retries reached, show offline page
      print('Max retries reached, showing offline page');
      await _showOfflinePage();
    }
  }

  // Reset retry counter on successful page load
  void _resetRetryCounter() {
    _retryCount = 0;
    _retryTimer?.cancel();
    _lastFailedUrl = null;
  }



  void _onItemTapped(int index) async {
    if (_paymentSetupLocationBlocked) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Allow location access ("Allow all the time" on Android) before leaving this step.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _selectedIndex = index;
      _isLoading = true;
    });

    // Reset retry counter when user manually navigates
    _resetRetryCounter();

    _controller.loadRequest(Uri.parse(_urls[index]));
  }
  
  // ignore: unused_element
  Future<void> _showOfflinePage() async {
    try {
      if (_isFoodnpalsConfirmationUrl(_lastFailedUrl) ||
          _isFoodnpalsPaymentSetupUrl(_lastFailedUrl)) {
        _resetRetryCounter();
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        await _navigateWebViewToHome();
        return;
      }

      // Cancel any pending timeout timer and retry timer
      _pageLoadTimer?.cancel();
      _retryTimer?.cancel();

      // Load bundled offline page from assets
      final html = await DefaultAssetBundle.of(context).loadString('android_asset/offline.html');
      
      // Modify the offline page to work with Flutter WebView
      final modifiedHtml = html.replaceAll(
        'onclick="retryConnection()"',
        'onclick="window.flutter_inappwebview.callHandler(\'retryConnection\')"'
      ).replaceAll(
        'setTimeout(() => {',
        'setTimeout(() => {'
      );
      
      await _controller.loadHtmlString(modifiedHtml);
      
      // Hide loading indicator
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading offline page: $e');
      // Fallback: show a simple error message with retry functionality
      await _controller.loadHtmlString('''
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
              body { 
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; 
                text-align: center; 
                padding: 50px; 
                background: linear-gradient(135deg, #4CBB17 0%, #50B849 100%);
                margin: 0;
                min-height: 100vh;
                display: flex;
                align-items: center;
                justify-content: center;
              }
              .container {
                background: white;
                border-radius: 20px;
                padding: 40px 30px;
                box-shadow: 0 20px 40px rgba(0,0,0,0.1);
                max-width: 400px;
                width: 90%;
              }
              .logo {
                background: #4CBB17;
                color: white;
                padding: 15px 25px;
                border-radius: 15px;
                font-size: 24px;
                font-weight: bold;
                margin-bottom: 30px;
                display: inline-block;
              }
              .icon { font-size: 64px; margin-bottom: 20px; opacity: 0.7; }
              h1 { font-size: 28px; margin-bottom: 15px; color: #333; font-weight: 600; }
              p { font-size: 16px; margin-bottom: 30px; line-height: 1.6; color: #666; }
              .retry-btn {
                background: #4CBB17; color: white; border: none; padding: 15px 30px;
                font-size: 16px; font-weight: 600; border-radius: 25px; cursor: pointer;
                transition: all 0.3s ease; box-shadow: 0 4px 15px rgba(76, 187, 23, 0.3);
                min-width: 120px;
              }
              .retry-btn:hover { background: #45a716; transform: translateY(-2px); }
              .retry-btn:active { transform: translateY(0); }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="logo">FoodnPals</div>
              <div class="icon">📱</div>
              <h1>Connection Issue</h1>
              <p>We're having trouble connecting to our servers.<br>
              Please check your internet connection and try again.</p>
              <button class="retry-btn" onclick="retryConnection()">Try Again</button>
            </div>
            <script>
              function retryConnection() {
                // Reset retry counter and try to reload the original URL
                window.location.reload();
              }
            </script>
          </body>
        </html>
      ''');
      
      // Hide loading indicator for fallback too
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _navigateWebViewToHome() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedIndex = 0;
    });
    await _controller.loadRequest(Uri.parse(_kHomeMobileUrl));
  }

  @override
  Widget build(BuildContext context) {
    // Check if user is signed in (not guest)
    final bool isSignedIn = widget.email != 'guest' && widget.token != 'guest';
    
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        final raw = await _controller.currentUrl() ?? _urlController.text;
        if (_isFoodnpalsPaymentSetupUrl(raw) ||
            _isFoodnpalsConfirmationUrl(raw) ||
            _paymentSetupLocationBlocked) {
          await _navigateWebViewToHome();
          return;
        }
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // if (kDebugMode) _buildDebugUrlBar(), // Temporarily hidden for testing
                  // WebView taking available space above bottom bar
                  Expanded(
                    child: WebViewWidget(
                      controller: _controller,
                      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
                        Factory<VerticalDragGestureRecognizer>(
                          VerticalDragGestureRecognizer.new,
                        ),
                      },
                    ),
                  ),
                  // Show bottom navigation only if signed in
                  if (isSignedIn) ...[
                    // Custom Bottom Bar with solid background
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0, left: 8, right: 8),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                          bottomLeft: Radius.circular(24),
                          bottomRight: Radius.circular(24),
                        ),
                        child: Container(
                          height: 63,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(24),
                              topRight: Radius.circular(24),
                              bottomLeft: Radius.circular(24),
                              bottomRight: Radius.circular(24),
                            ),
                            border: Border.all(
                              color: Colors.grey.withOpacity(0.2),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 20,
                                offset: const Offset(0, -2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildNavIcon(Icons.home, 0),
                              _buildNavIcon(Icons.calendar_month, 1),
                              _buildNavIcon(Icons.shopping_bag, 2),
                              _buildNavIcon(Icons.person, 3),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Sign In Now button for guest users
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0, left: 8, right: 8),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                          bottomLeft: Radius.circular(24),
                          bottomRight: Radius.circular(24),
                        ),
                        child: Container(
                          height: 63,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(24),
                              topRight: Radius.circular(24),
                              bottomLeft: Radius.circular(24),
                              bottomRight: Radius.circular(24),
                            ),
                            border: Border.all(
                              color: Colors.grey.withOpacity(0.2),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 20,
                                offset: const Offset(0, -2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: SizedBox(
                              width: double.infinity,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: ElevatedButton(
                                  onPressed: () {
                                    // Navigate to login screen
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(
                                        builder: (context) => LoginScreen(
                                          onLogin: (token, email) {
                                            // Handle login and navigate to main app
                                            Navigator.of(context).pushReplacement(
                                              MaterialPageRoute(
                                                builder: (context) => WebViewScreen(
                                                  email: email,
                                                  token: token,
                                                  onLogout: () {},
                                                  initialUrl: 'https://foodnpals.com/MobileLogin.php?email=${Uri.encodeComponent(email)}&token=${Uri.encodeComponent(token)}',
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF4CBB17),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                  ),
                                  child: const Text(
                                    'Sign In Now',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              // Loading overlay — fully opaque so WebView's empty canvas never shows
              AnimatedOpacity(
                opacity: _isLoading ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 350),
                onEnd: () {
                  // After fade-out completes, the overlay is invisible but still
                  // in the widget tree — that's fine, it doesn't intercept touches
                  // when opacity is 0 and we use IgnorePointer.
                },
                child: IgnorePointer(
                  ignoring: !_isLoading,
                  child: Container(
                    color: Colors.white,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/images/loading.gif',
                            width: 100,
                            height: 100,
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Loading...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF4CBB17),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_paymentSetupLocationBlocked)
                Positioned.fill(
                  child: Material(
                    color: Colors.white,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 56,
                                color: Color(0xFF4CBB17),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Location access required',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'We need your location permission to track your journey to the restaurant. So the restaurant can prepare your table according to your arrival time. '
                                'On Android, choose "Allow all the time". ',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade800,
                                  height: 1.45,
                                ),
                              ),
                              const SizedBox(height: 20),
                              const LocationPermissionInstructionVideo(),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: () async {
                                  await Geolocator.openAppSettings();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4CBB17),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Open Settings',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: () async {
                                  await _navigateWebViewToHome();
                                },
                                child: const Text('Go back'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildDebugUrlBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.grey[200],
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _urlController,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                hintText: 'Enter URL',
                border: InputBorder.none,
              ),
              onSubmitted: (url) {
                if (Uri.tryParse(url)?.isAbsolute ?? false) {
                  _controller.loadRequest(Uri.parse(url));
                }
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () {
              final url = _urlController.text.trim();
              if (Uri.tryParse(url)?.isAbsolute ?? false) {
                _controller.loadRequest(Uri.parse(url));
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavIcon(IconData icon, int index) {
    final isActive = _selectedIndex == index;
    return GestureDetector(
      onTap: () => _onItemTapped(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 18),
        decoration: BoxDecoration(
          color: isActive ? const Color(0x1A4CBB17) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          icon,
          size: 30,
          color: isActive ? const Color(0xFF4CBB17) : Colors.grey[600],
        ),
      ),
    );
  }
}
