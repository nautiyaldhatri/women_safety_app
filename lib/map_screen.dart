import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class MapScreen extends StatefulWidget {
  final bool isEmergencyActive;
  final String? alertId;

  const MapScreen({
    super.key,
    this.isEmergencyActive = false,
    this.alertId,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng _currentPosition = const LatLng(26.4778, 80.2242); // Default fallback
  bool _isLoading = true;
  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    _initLiveLocation();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  /// Fetches initial location and subscribes to continuous GPS updates
  Future<void> _initLiveLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
          _isLoading = false;
        });
      }

      // Subscribe to real-time location stream for live pin movement
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5, // Update map every 5 meters moved
        ),
      ).listen((Position newPos) {
        if (mounted) {
          setState(() {
            _currentPosition = LatLng(newPos.latitude, newPos.longitude);
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _recenterMap() {
    _mapController.move(_currentPosition, 16.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12121A),
      appBar: AppBar(
        title: const Text('Live Safety Map'),
        backgroundColor: const Color(0xFF1E1E2C),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location, color: Colors.greenAccent),
            onPressed: _recenterMap,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Fixed typo
          children: [
            CircularProgressIndicator(color: Colors.redAccent),
            SizedBox(height: 16),
            Text(
              'Acquiring live GPS coordinates...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      )
          : Stack(
        children: [
          // INTERACTIVE OPENSTREETMAP
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: 16.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.women_safety_app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentPosition,
                    width: 60,
                    height: 60,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.redAccent.withOpacity(0.3),
                          ),
                        ),
                        const CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.redAccent,
                          child: Icon(
                            Icons.person_pin_circle,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // TOP COORDINATES CARD
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2C).withOpacity(0.95),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: widget.isEmergencyActive ? Colors.redAccent : Colors.white10,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.isEmergencyActive ? Icons.warning : Icons.gps_fixed,
                    color: widget.isEmergencyActive ? Colors.redAccent : Colors.greenAccent,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.isEmergencyActive
                              ? "🚨 LIVE EMERGENCY TRACKING ACTIVE"
                              : "Live GPS Coordinates",
                          style: TextStyle(
                            color: widget.isEmergencyActive ? Colors.redAccent : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Lat: ${_currentPosition.latitude.toStringAsFixed(5)}, Lng: ${_currentPosition.longitude.toStringAsFixed(5)}",
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // FLOATING RECENTER BUTTON
          Positioned(
            bottom: 24,
            right: 16,
            child: FloatingActionButton.extended(
              onPressed: _recenterMap,
              backgroundColor: const Color(0xFF1E1E2C),
              icon: const Icon(Icons.center_focus_strong, color: Colors.greenAccent),
              label: const Text(
                'Recenter',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}