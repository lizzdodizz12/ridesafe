import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'emergency_service.dart';

typedef CrashDetectedCallback = Future<void> Function();

class CrashDetectionService {
  static final CrashDetectionService _instance =
      CrashDetectionService._internal();

  factory CrashDetectionService() {
    return _instance;
  }

  CrashDetectionService._internal();

  bool isMonitoring = false;
  double currentSpeed = 0.0; // km/h
  double maxAcceleration = 0.0; // magnitude
  double maxGyroscope = 0.0; // magnitude

  // Configurable thresholds
  static const double SPEED_THRESHOLD =
      20.0; // km/h (minimum speed to detect crash)
  static const double ACCELERATION_THRESHOLD = 35.0; // m/s² (sudden impact)
  static const double GYROSCOPE_THRESHOLD = 5.0; // rad/s (abnormal rotation)
  static const Duration CONFIRMATION_TIME = Duration(seconds: 15);

  late StreamSubscription<AccelerometerEvent> accelSubscription;
  late StreamSubscription<GyroscopeEvent> gyroSubscription;
  late StreamSubscription<Position> positionSubscription;

  Timer? confirmationTimer;
  CrashDetectedCallback? onCrashDetected;

  // Start monitoring sensors
  Future<void> startMonitoring({
    required CrashDetectedCallback onCrashDetected,
  }) async {
    if (isMonitoring) return;

    isMonitoring = true;
    this.onCrashDetected = onCrashDetected;
    maxAcceleration = 0.0;
    maxGyroscope = 0.0;

    // Monitor accelerometer
    accelSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      final magnitude = _calculateMagnitude(event.x, event.y, event.z);
      if (magnitude > maxAcceleration) {
        maxAcceleration = magnitude;
      }

      // Check for sudden impact
      if (magnitude > ACCELERATION_THRESHOLD &&
          currentSpeed > SPEED_THRESHOLD) {
        _onPotentialCrash(
          'High acceleration detected: ${magnitude.toStringAsFixed(2)} m/s²',
        );
      }
    });

    // Monitor gyroscope
    gyroSubscription = gyroscopeEvents.listen((GyroscopeEvent event) {
      final magnitude = _calculateMagnitude(event.x, event.y, event.z);
      if (magnitude > maxGyroscope) {
        maxGyroscope = magnitude;
      }

      if (magnitude > GYROSCOPE_THRESHOLD && currentSpeed > SPEED_THRESHOLD) {
        _onPotentialCrash(
          'Abnormal rotation detected: ${magnitude.toStringAsFixed(2)} rad/s',
        );
      }
    });

    // Monitor GPS speed
    positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 2,
          ),
        ).listen((Position position) {
          currentSpeed = position.speed * 3.6; // Convert m/s to km/h
        });
  }

  // Stop monitoring
  void stopMonitoring() {
    if (!isMonitoring) return;

    isMonitoring = false;
    accelSubscription.cancel();
    gyroSubscription.cancel();
    positionSubscription.cancel();
    confirmationTimer?.cancel();
    maxAcceleration = 0.0;
    maxGyroscope = 0.0;
    currentSpeed = 0.0;
  }

  // Calculate magnitude of acceleration/rotation
  double _calculateMagnitude(double x, double y, double z) {
    return (x * x + y * y + z * z).toDouble() *
        0.5; // Simplified for performance
  }

  // Handle potential crash
  void _onPotentialCrash(String reason) {
    print('🚨 Crash Detection Alert: $reason');
    print('   Speed: ${currentSpeed.toStringAsFixed(1)} km/h');
    print('   Acceleration: ${maxAcceleration.toStringAsFixed(2)} m/s²');
    print('   Rotation: ${maxGyroscope.toStringAsFixed(2)} rad/s');

    // Check if user responds within 15 seconds
    confirmationTimer?.cancel();
    confirmationTimer = Timer(CONFIRMATION_TIME, () async {
      print('🚨 CRASH CONFIRMED - Triggering SOS!');
      await onCrashDetected?.call();
    });
  }

  // User dismisses crash alert
  void dismissCrashAlert() {
    print('✅ Crash alert dismissed by user');
    confirmationTimer?.cancel();
    maxAcceleration = 0.0;
    maxGyroscope = 0.0;
  }

  // Get current status
  Map<String, dynamic> getStatus() {
    return {
      'isMonitoring': isMonitoring,
      'speed': currentSpeed.toStringAsFixed(1),
      'acceleration': maxAcceleration.toStringAsFixed(2),
      'rotation': maxGyroscope.toStringAsFixed(2),
    };
  }
}
