import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  runApp(const MaterialApp(home: AppStarter(), debugShowCheckedModeBanner: false));
}

// --- THEME CONSTANTS ---
final Color kCyberBlack = Color(0xFF121212);
final Color kNeonBlue = Color(0xFF00E5FF);
final Color kNeonRed = Color(0xFFFF2A68);
final Color kTerminalGreen = Color(0xFF00FF41);

// --- 1. APP STARTER ---
class AppStarter extends StatefulWidget {
  const AppStarter({super.key});
  @override
  State<AppStarter> createState() => _AppStarterState();
}

class _AppStarterState extends State<AppStarter> {
  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  void _checkLogin() async {
    await Future.delayed(Duration(seconds: 2));
    SharedPreferences prefs = await SharedPreferences.getInstance();
    
    if (prefs.getString('emergency_phone') != null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const GuardianHome()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kCyberBlack,
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_moon, size: 80, color: kNeonBlue),
          SizedBox(height: 20),
          CircularProgressIndicator(color: kNeonBlue),
        ],
      ),
    ),
  );
}

// --- 2. LOGIN SCREEN (CYBER STYLE) ---
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  void _saveAndLogin() async {
    if (_nameController.text.isEmpty || _phoneController.text.isEmpty) return;
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _nameController.text);
    await prefs.setString('emergency_phone', _phoneController.text);
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const GuardianHome()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCyberBlack,
      body: SingleChildScrollView(
        child: Container(
          height: MediaQuery.of(context).size.height,
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_moon_outlined, size: 100, color: kNeonBlue),
              SizedBox(height: 20),
              Text("GUARDIAN", style: GoogleFonts.orbitron(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 4)),
              Text("ZERO TOUCH INTERFACE", style: GoogleFonts.sourceCodePro(color: kNeonBlue, fontSize: 12, letterSpacing: 2)),
              SizedBox(height: 50),
              _cyberInput(_nameController, "AGENT NAME", Icons.person),
              SizedBox(height: 20),
              _cyberInput(_phoneController, "UPLINK NUMBER (+91...)", Icons.wifi_tethering),
              SizedBox(height: 40),
              ElevatedButton(
                onPressed: _saveAndLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kNeonBlue,
                  foregroundColor: Colors.black,
                  padding: EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  shape: BeveledRectangleBorder(borderRadius: BorderRadius.circular(5)),
                ),
                child: Text("INITIALIZE SYSTEM", style: GoogleFonts.orbitron(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cyberInput(TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      style: TextStyle(color: Colors.white),
      keyboardType: label.contains("NUMBER") ? TextInputType.phone : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey),
        prefixIcon: Icon(icon, color: kNeonBlue),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey[800]!)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: kNeonBlue, width: 2)),
        filled: true,
        fillColor: Colors.grey[900],
      ),
    );
  }
}

// --- 3. DASHBOARD WITH RADAR ANIMATION ---
class GuardianHome extends StatefulWidget {
  const GuardianHome({super.key});
  @override
  State<GuardianHome> createState() => _GuardianHomeState();
}

class _GuardianHomeState extends State<GuardianHome> with TickerProviderStateMixin, WidgetsBindingObserver {
  final Telephony telephony = Telephony.instance;
  late stt.SpeechToText _speech;
  late AnimationController _pulseController;
  
  bool _isListening = false;
  bool _isSOSActive = false;
  String _statusText = "SYSTEM STANDBY";
  String _aiLog = "> Waiting for command...";
  int _countdown = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _speech = stt.SpeechToText();
    _pulseController = AnimationController(vsync: this, duration: Duration(seconds: 2))..repeat();
    _requestPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _isSOSActive) {
      _cancelSOS("Power Button Override");
    }
  }

  Future<void> _requestPermissions() async {
    await [Permission.sms, Permission.location, Permission.microphone, Permission.speech].request();
  }

  void _toggleSystem() async {
    if (_isListening) {
      setState(() { _isListening = false; _statusText = "SYSTEM STANDBY"; _aiLog = "> System Paused."; });
      _speech.stop();
    } else {
      bool available = await _speech.initialize(
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') && _isListening && !_isSOSActive) {
            _startListening();
          }
        },
        onError: (e) {
          if (_isListening && !_isSOSActive) _startListening();
        }
      );

      if (available) {
        setState(() { _isListening = true; });
        _startListening();
      }
    }
  }

  void _startListening() {
    if (!_isListening || _isSOSActive) return;
    setState(() { _statusText = "SCANNING AUDIO..."; _aiLog = "> Scanning for threats..."; });
    _speech.listen(
      onResult: (val) {
        if(val.recognizedWords.isNotEmpty) setState(() => _aiLog = "> Detected: [${val.recognizedWords}]");
        if (val.recognizedWords.toLowerCase().contains("help") || val.recognizedWords.toLowerCase().contains("emergency")) {
          _triggerSOS();
        }
      },
      listenFor: Duration(seconds: 20),
      pauseFor: Duration(seconds: 3),
      cancelOnError: false,
      partialResults: true,
      listenMode: stt.ListenMode.dictation
    );
  }

  void _triggerSOS() {
    _speech.stop();
    setState(() { _isListening = false; _isSOSActive = true; _countdown = 5; });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown == 0) {
        timer.cancel();
        _sendAlert();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  void _cancelSOS(String reason) {
    _timer?.cancel();
    setState(() { _isSOSActive = false; _statusText = "SYSTEM STANDBY"; _aiLog = "> Aborted: $reason"; _isListening = false; });
  }

  Future<void> _sendAlert() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String phone = prefs.getString('emergency_phone') ?? "";
    String name = prefs.getString('user_name') ?? "Agent";

    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      
      // FIXED LINK HERE:
      String link = "https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}";
      
      String msg = "🚨 ZERO TOUCH ALERT 🚨\n$name is in danger.\nLocation: $link";
      
      await telephony.sendSms(to: phone, message: msg, isMultipart: true);
      setState(() { _isSOSActive = false; _aiLog = "> ✅ DATA PACKET SENT"; });
      _showSuccessDialog();
    } catch (e) {
      setState(() => _aiLog = "> Error: $e");
    }
  }

  void _showSuccessDialog() {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: kCyberBlack,
      title: Text("ALERT SENT", style: TextStyle(color: kTerminalGreen)),
      content: Text("Emergency contacts notified.", style: TextStyle(color: Colors.white)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_isSOSActive) {
      return Scaffold(
        backgroundColor: kNeonRed,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.warning, size: 80, color: Colors.white),
              Text("THREAT DETECTED", style: GoogleFonts.orbitron(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              Text("$_countdown", style: GoogleFonts.orbitron(color: Colors.white, fontSize: 120)),
              ElevatedButton(
                onPressed: () => _cancelSOS("Manual Abort"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kNeonRed),
                child: Text("ABORT SEQUENCE"),
              )
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: kCyberBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text("GUARDIAN", style: GoogleFonts.orbitron(color: kNeonBlue, letterSpacing: 2)),
        centerTitle: true,
        actions: [IconButton(icon: Icon(Icons.power_settings_new, color: kNeonRed), onPressed: () async {
           SharedPreferences prefs = await SharedPreferences.getInstance(); await prefs.clear();
           Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
        })],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 10),
            color: _isListening ? kNeonBlue.withOpacity(0.1) : Colors.transparent,
            child: Text(_statusText, textAlign: TextAlign.center, style: GoogleFonts.sourceCodePro(color: _isListening ? kNeonBlue : Colors.grey, letterSpacing: 3)),
          ),
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: _toggleSystem,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_isListening)
                      ScaleTransition(
                        scale: Tween(begin: 1.0, end: 1.5).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut)),
                        child: FadeTransition(
                          opacity: Tween(begin: 0.5, end: 0.0).animate(_pulseController),
                          child: Container(width: 200, height: 200, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kNeonBlue, width: 2))),
                        ),
                      ),
                    Container(
                      width: 160, height: 160,
                      decoration: BoxDecoration(
                        color: kCyberBlack,
                        shape: BoxShape.circle,
                        border: Border.all(color: _isListening ? kNeonBlue : Colors.grey[800]!, width: 4),
                        boxShadow: [BoxShadow(color: _isListening ? kNeonBlue.withOpacity(0.5) : Colors.transparent, blurRadius: 30)],
                      ),
                      child: Icon(Icons.fingerprint, size: 80, color: _isListening ? kNeonBlue : Colors.grey[800]),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity, height: 150, margin: EdgeInsets.all(20), padding: EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.black, border: Border.all(color: _isListening ? kTerminalGreen : Colors.grey[800]!), borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("TERMINAL OUTPUT:", style: GoogleFonts.sourceCodePro(color: Colors.grey, fontSize: 10)),
                Divider(color: Colors.grey[800]),
                Expanded(child: Text(_aiLog, style: GoogleFonts.sourceCodePro(color: kTerminalGreen))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}