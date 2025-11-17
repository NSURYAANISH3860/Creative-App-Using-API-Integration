import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

void main() {
  runApp(WeatherApiApp());
}

class WeatherApiApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quick Weather (Open-Meteo)',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: WeatherHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class WeatherHomePage extends StatefulWidget {
  @override
  State<WeatherHomePage> createState() => _WeatherHomePageState();
}

class _WeatherHomePageState extends State<WeatherHomePage> {
  final _controller = TextEditingController(text: "Hyderabad");
  bool _loading = false;
  String? _error;
  WeatherResult? _result;

  Future<void> _fetchWeatherFor(String city) async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      final place = await _geocodeCity(city);
      if (place == null) {
        setState(() {
          _error = "City not found: $city";
          _loading = false;
        });
        return;
      }

      final weather = await _getCurrentWeather(place.lat, place.lon);
      if (weather == null) {
        setState(() {
          _error = "Unable to fetch weather for ${place.displayName}";
        });
      } else {
        setState(() {
          _result = WeatherResult(place.displayName, weather);
        });
      }
    } catch (e) {
      setState(() {
        _error = "Error: ${e.toString()}";
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<_Place?> _geocodeCity(String city) async {
    final q = Uri.encodeQueryComponent(city);
    final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$q&format=json&limit=1');
    final resp = await http.get(url, headers: {'User-Agent': 'flutter-app/1.0 (your-email@example.com)'});
    if (resp.statusCode != 200) return null;
    final List data = jsonDecode(resp.body);
    if (data.isEmpty) return null;
    final obj = data[0];
    final lat = double.tryParse(obj['lat'].toString());
    final lon = double.tryParse(obj['lon'].toString());
    if (lat == null || lon == null) return null;
    final name = obj['display_name'] ?? city;
    return _Place(lat, lon, name);
  }

  Future<_Weather?> _getCurrentWeather(double lat, double lon) async {
    final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true&temperature_unit=celsius&windspeed_unit=kmh');
    final resp = await http.get(url);
    if (resp.statusCode != 200) return null;
    final map = jsonDecode(resp.body);
    if (map['current_weather'] == null) return null;
    final cw = map['current_weather'];
    final temp = (cw['temperature'] as num).toDouble();
    final wind = (cw['windspeed'] as num).toDouble();
    final code = cw['weathercode'];
    final time = cw['time'];
    return _Weather(temp, wind, code, time);
  }

  String _mapWeatherCodeToText(int code) {
    // Simple mapping from Open-Meteo weather codes
    if (code == 0) return 'Clear sky';
    if (code == 1 || code == 2 || code == 3) return 'Mainly clear / partly cloudy';
    if (code >= 45 && code <= 48) return 'Fog / depositing rime fog';
    if (code >= 51 && code <= 57) return 'Drizzle';
    if (code >= 61 && code <= 67) return 'Rain';
    if (code >= 71 && code <= 77) return 'Snow / Ice';
    if (code >= 80 && code <= 82) return 'Rain showers';
    if (code >= 95 && code <= 99) return 'Thunderstorm or heavy precipitation';
    return 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Quick Weather (Open-Meteo)'),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => _fetchWeatherFor(v.trim()),
              decoration: InputDecoration(
                labelText: 'City name',
                hintText: 'Enter city (e.g., London, New York, Hyderabad)',
                suffixIcon: IconButton(
                  icon: Icon(Icons.search),
                  onPressed: _loading ? null : () => _fetchWeatherFor(_controller.text.trim()),
                ),
              ),
            ),
            SizedBox(height: 16),
            if (_loading)
              Center(child: CircularProgressIndicator())
            else if (_error != null)
              Card(
                color: Colors.red[50],
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red),
                      SizedBox(width: 10),
                      Expanded(child: Text(_error!, style: TextStyle(color: Colors.red[900]))),
                    ],
                  ),
                ),
              )
            else if (_result != null)
              Expanded(child: _buildWeatherCard(_result!))
            else
              Expanded(
                child: Center(
                  child: Text('Search for a city to view current weather.', textAlign: TextAlign.center),
                ),
              ),
            SizedBox(height: 12),
            Text('Data sources: Nominatim (geocoding) & Open-Meteo'),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherCard(WeatherResult r) {
    final w = r.weather;
    final dt = DateFormat.yMMMEd().add_jm().format(DateTime.parse(w.time).toLocal());
    final desc = _mapWeatherCodeToText(w.weatherCode);
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.placeName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text('As of: $dt', style: TextStyle(color: Colors.grey[700])),
            Divider(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _metricTile(Icons.thermostat_outlined, '${w.temperature.toStringAsFixed(1)} °C', 'Temp'),
                _metricTile(Icons.air, '${w.windSpeed.toStringAsFixed(1)} km/h', 'Wind'),
                _metricTile(Icons.cloud, desc, 'Condition', flex: 2),
              ],
            ),
            Spacer(),
            Align(
              alignment: Alignment.bottomRight,
              child: Text('Powered by Open-Meteo', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            )
          ],
        ),
      ),
    );
  }

  Widget _metricTile(IconData icon, String value, String label, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Column(
        children: [
          Icon(icon, size: 32, color: Colors.blueAccent),
          SizedBox(height: 6),
          Text(value, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(height: 4),
          Text(label, style: TextStyle(color: Colors.grey[700])),
        ],
      ),
    );
  }
}

class _Place {
  final double lat;
  final double lon;
  final String displayName;
  _Place(this.lat, this.lon, this.displayName);
}

class _Weather {
  final double temperature;
  final double windSpeed;
  final int weatherCode;
  final String time;
  _Weather(this.temperature, this.windSpeed, this.weatherCode, this.time);
}

class WeatherResult {
  final String placeName;
  final _Weather weather;
  WeatherResult(this.placeName, this.weather);
}
