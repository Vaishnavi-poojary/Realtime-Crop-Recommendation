// lib/main.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

const String BACKEND_IP =
    "192.168.1.109"; // <-- update if your laptop IP changes
const String BACKEND_PORT = "5000";
final Uri PREDICT_URI = Uri.parse(
  "http://$BACKEND_IP:$BACKEND_PORT/predict/crop",
);

// Put your OpenWeather API key here (or keep the current one if it's valid)
const String OPENWEATHER_API_KEY = "1eb2298216b09cd00d3a80c6cfa7b257";

void main() {
  runApp(const CropPolishApp());
}

class CropPolishApp extends StatelessWidget {
  const CropPolishApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crop Recommender',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          brightness: Brightness.dark,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white12,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // controllers (same names as before)
  final TextEditingController nCtl = TextEditingController();
  final TextEditingController pCtl = TextEditingController();
  final TextEditingController kCtl = TextEditingController();
  final TextEditingController tempCtl = TextEditingController();
  final TextEditingController humCtl = TextEditingController();
  final TextEditingController phCtl = TextEditingController();
  final TextEditingController rainCtl = TextEditingController();

  String resultText = "";
  String predictedCrop = "";
  bool loading = false;
  bool weatherLoading = false;
  Map<String, dynamic>? lastPayload;
  Map<String, dynamic>? lastResponse;

  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    nCtl.dispose();
    pCtl.dispose();
    kCtl.dispose();
    tempCtl.dispose();
    humCtl.dispose();
    phCtl.dispose();
    rainCtl.dispose();
    super.dispose();
  }

  bool _isNumeric(String s) => double.tryParse(s) != null;

  // -------------------------------
  //     GET ML RECOMMENDATION
  // -------------------------------
  Future<void> _getRecommendation() async {
    setState(() {
      resultText = "";
      predictedCrop = "";
      lastResponse = null;
    });

    final n = nCtl.text.trim();
    final p = pCtl.text.trim();
    final k = kCtl.text.trim();
    final temp = tempCtl.text.trim();
    final hum = humCtl.text.trim();
    final ph = phCtl.text.trim();
    final rain = rainCtl.text.trim();

    if (![n, p, k, temp, hum, ph, rain].every((e) => e.isNotEmpty)) {
      setState(() => resultText =
          "Please fill ALL fields (including auto-filled weather).");
      return;
    }
    if (![n, p, k, temp, hum, ph, rain].every(_isNumeric)) {
      setState(() => resultText = "All fields must be numeric.");
      return;
    }

    // Build payload that we will send to backend
    final body = {
      "N": double.parse(n),
      "P": double.parse(p),
      "K": double.parse(k),
      "temperature": double.parse(temp),
      "humidity": double.parse(hum),
      "ph": double.parse(ph),
      "rainfall": double.parse(rain),
    };

    // Save payload for debug view
    lastPayload = body;

    setState(() {
      loading = true;
      resultText = "Requesting recommendation from backend...";
    });

    try {
      final response = await http
          .post(
            PREDICT_URI,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        lastResponse = data is Map<String, dynamic> ? data : {"resp": data};

        // Accept several possible field names that server might return
        final pred = data["recommended_crop"] ??
            data["recommended"] ??
            data["prediction"] ??
            data["crop"] ??
            data["result"] ??
            (data is String ? data : null);

        setState(() {
          predictedCrop = pred?.toString() ?? "Unknown";
          resultText = "Recommendation received from backend.";
        });
      } else {
        // show server body so you can debug model/server behavior
        setState(() {
          resultText =
              "Server error (${response.statusCode}). See debug below.";
          lastResponse = {
            "status": response.statusCode,
            "body": response.body,
          };
        });
      }
    } catch (e) {
      setState(() {
        resultText =
            "Network error. Make sure backend is running on $BACKEND_IP:$BACKEND_PORT\nError: $e";
      });
    } finally {
      setState(() => loading = false);
    }
  }

  // -------------------------------
  //     AUTO-FETCH WEATHER
  // -------------------------------
  Future<void> fetchWeather(String city) async {
    setState(() {
      weatherLoading = true;
      resultText = "Fetching weather...";
    });

    final url = Uri.parse(
        "https://api.openweathermap.org/data/2.5/weather?q=${Uri.encodeQueryComponent(city)}&appid=$OPENWEATHER_API_KEY&units=metric");

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final temp = (data["main"] != null && data["main"]["temp"] != null)
            ? (data["main"]["temp"] as num).toDouble()
            : null;
        final humidity =
            (data["main"] != null && data["main"]["humidity"] != null)
                ? (data["main"]["humidity"] as num).toInt()
                : null;
        // rain can be in "rain" -> "1h" or "3h" or absent
        double rainfall = 0;
        if (data["rain"] != null) {
          rainfall = (data["rain"]["1h"] ?? data["rain"]["3h"] ?? 0).toDouble();
        }

        if (temp != null) tempCtl.text = temp.toString();
        if (humidity != null) humCtl.text = humidity.toString();
        rainCtl.text = rainfall.toString();

        setState(() {
          resultText = "Weather auto-filled from $city";
        });
      } else {
        setState(() {
          resultText = "Weather failed (${response.statusCode}).";
        });
      }
    } catch (e) {
      setState(() {
        resultText = "Weather API error: $e";
      });
    } finally {
      setState(() => weatherLoading = false);
    }
  }

  // -------------------------------
  //        SMALL UI HELPERS
  // -------------------------------
  Widget _inputRow(IconData icon, String label, TextEditingController ctl,
      {String hint = ""}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: Colors.white70),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: ctl,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          child
        ],
      ),
    );
  }

  // -------------------------------
  //              UI
  // -------------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(children: [
          // gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          // content
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // header
              Row(
                children: [
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        "Smart Crop Recommender",
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 6),
                      Text(
                        "Enter soil & weather data — or auto-fill weather.",
                        style: TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                    ],
                  )),
                  ScaleTransition(
                    scale: Tween(begin: 0.95, end: 1.05).animate(
                        CurvedAnimation(
                            parent: _shimmerController,
                            curve: Curves.easeInOut)),
                    child: Container(
                      height: 68,
                      width: 68,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.agriculture_rounded, size: 34),
                    ),
                  )
                ],
              ),

              const SizedBox(height: 12),

              // inputs card
              _sectionCard(
                title: "Soil Inputs",
                child: Column(
                  children: [
                    _inputRow(Icons.grass, "Nitrogen (N)", nCtl),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                            child: _inputRow(
                                Icons.scatter_plot, "Phosphorus (P)", pCtl)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _inputRow(
                                Icons.bubble_chart, "Potassium (K)", kCtl)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                            child: _inputRow(Icons.thermostat_outlined,
                                "Temperature (°C)", tempCtl)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _inputRow(Icons.water_drop_outlined,
                                "Humidity (%)", humCtl)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _inputRow(Icons.eco, "pH", phCtl)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _inputRow(
                                Icons.umbrella, "Rainfall (mm)", rainCtl)),
                      ],
                    ),
                  ],
                ),
              ),

              // weather auto-fill card
              _sectionCard(
                title: "Auto-Fill Weather",
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: "City (e.g. Mangalore)",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (city) {
                        if (city.trim().isNotEmpty) fetchWeather(city.trim());
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: weatherLoading
                              ? null
                              : () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) {
                                      final cityCtl = TextEditingController();
                                      return AlertDialog(
                                        title: const Text("Enter city"),
                                        content: TextField(
                                          controller: cityCtl,
                                          decoration: const InputDecoration(
                                              labelText: "City name"),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () {
                                              Navigator.pop(ctx);
                                            },
                                            child: const Text("Cancel"),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              final city = cityCtl.text.trim();
                                              Navigator.pop(ctx);
                                              if (city.isNotEmpty)
                                                fetchWeather(city);
                                            },
                                            child: const Text("Fetch"),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                          icon: const Icon(Icons.cloud),
                          label: weatherLoading
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Text("Auto-Fill Weather"),
                          style: ButtonStyle(
                            shape: MaterialStateProperty.all(
                                RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12))),
                          ),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // action buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: loading ? null : _getRecommendation,
                      style: ButtonStyle(
                        padding: MaterialStateProperty.all(
                            const EdgeInsets.symmetric(vertical: 14)),
                        shape: MaterialStateProperty.all(RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                        elevation: MaterialStateProperty.all(6.0),
                      ),
                      child: loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text("Get Recommendation",
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // result card
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: predictedCrop.isEmpty
                    ? Container(
                        key: const ValueKey(0),
                        padding: const EdgeInsets.all(14),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(resultText.isEmpty
                            ? "No recommendation yet"
                            : resultText),
                      )
                    : Container(
                        key: const ValueKey(1),
                        padding: const EdgeInsets.all(12),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.42),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.green.shade800,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child:
                                  const Icon(Icons.check, color: Colors.white),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Recommended crop".toUpperCase(),
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.white70)),
                                  const SizedBox(height: 6),
                                  Text(predictedCrop,
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 6),
                                  Text(resultText,
                                      style: const TextStyle(
                                          color: Colors.white70)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // small friendly emoji for crop (no external asset)
                            const Text("🌾", style: TextStyle(fontSize: 28)),
                          ],
                        ),
                      ),
              ),

              const SizedBox(height: 12),

              // Debug: show last payload & last response if available
              if (lastPayload != null)
                _sectionCard(
                  title: "Last payload sent (debug)",
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(lastPayload),
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),

              if (lastResponse != null)
                _sectionCard(
                  title: "Last response (debug)",
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(lastResponse),
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),

              const SizedBox(height: 32),
            ]),
          ),
        ]),
      ),
    );
  }
}
