import Foundation
import CoreLocation

// MARK: - Location Service

/// Resolves the user's current place name (and optional coordinates)
/// using CoreLocation + reverse geocoding.
///
/// Users will see a system location-permission prompt on first use.
/// If the user denies permission or location is unavailable,
/// `locationName` is `nil` and coordinates are `nil` — the record
/// save still proceeds.
///
/// - Important: Use ``shared`` singleton everywhere.  Do **not** create
///   multiple instances — each would own its own `CLLocationManager`
///   and cause delegate races.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    /// Shared singleton — used by both ``ContentView`` and ``AddRecordView``.
    static let shared = LocationService()

    private let manager = CLLocationManager()

    /// The active continuation, or `nil` when no request is in flight.
    /// Only one location request may be active at a time.
    private var continuation: CheckedContinuation<LocationResult, Never>?

    // MARK: - Init

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.delegate = self
        print("[Location] init, authorization =", manager.authorizationStatus.rawValue)
    }

    // MARK: - Public API

    /// Requests location permission on app launch (fire‑and‑forget).
    /// Call this once during `ContentView.onAppear`.
    nonisolated func requestPermission() {
        // Must dispatch to main actor because CLLocationManager is not Sendable.
        Task { @MainActor in
            let status = manager.authorizationStatus
            print("[Location] requestPermission, status =", status.rawValue)
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
            }
        }
    }

    typealias LocationResult = (locationName: String?,
                                latitude: Double?,
                                longitude: Double?)

    /// Returns the current place name and coordinates.
    ///
    /// If the user denies location or it fails, returns fallback values
    /// so saving can proceed.
    func requestLocation() async -> LocationResult {
        await withCheckedContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(returning: (nil, nil, nil))
                return
            }

            // ── If a previous continuation was never consumed, close it ──
            if self.continuation != nil {
                print("[Location] ⚠️ previous continuation still alive, resuming nil")
                self.continuation?.resume(returning: (nil, nil, nil))
                self.continuation = nil
            }

            self.continuation = continuation

            let status = manager.authorizationStatus
            print("[Location] requestLocation, authorization =", status.rawValue)

            switch status {
            case .notDetermined:
                print("[Location] → requesting permission (notDetermined)")
                manager.requestWhenInUseAuthorization()
                // Continuation stays alive; delegate will handle auth change
                // and then call requestLocation().

            case .authorizedAlways, .authorizedWhenInUse:
                print("[Location] → requesting one‑shot location")
                manager.requestLocation()

            case .denied, .restricted:
                print("[Location] → denied / restricted")
                self.continuation?.resume(returning: ("未知地点", nil, nil))
                self.continuation = nil

            @unknown default:
                print("[Location] → unknown status")
                self.continuation?.resume(returning: (nil, nil, nil))
                self.continuation = nil
            }

            // ── Timeout: 15 seconds ──────────────────────────────
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard let self, self.continuation != nil else { return }
                print("[Location] ⏰ timeout after 15 s, resuming with fallback")
                self.continuation?.resume(returning: ("定位失败", nil, nil))
                self.continuation = nil
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        print("[Location] didChangeAuthorization →", status.rawValue)

        // Only kick off a location request if we are **already waiting**
        // for one (continuation != nil).  This prevents a premature
        // `requestLocation()` during initialisation when the delegate
        // is first assigned.
        guard status != .notDetermined, continuation != nil else {
            print("[Location]   → skipped (no active continuation)")
            return
        }

        print("[Location]   → user responded, requesting one‑shot location")
        manager.requestLocation()
    }

    func locationManager(
        _: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else {
            print("[Location] didUpdateLocations – empty, resuming nil")
            continuation?.resume(returning: (nil, nil, nil))
            continuation = nil
            return
        }

        print("[Location] didUpdateLocations – location acquired (lat=\(location.coordinate.latitude))")
        print("[Location] reverse geocode start")

        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            let name: String = {
                guard let mk = placemarks?.first else {
                    print("[Location] reverse geocode – no placemarks")
                    return "未知地点"
                }
                let result = mk.locality ?? mk.name ?? "未知地点"
                print("[Location] reverse geocode – result:", result)
                return result
            }()

            let result: LocationResult = (
                locationName: name,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )

            self?.continuation?.resume(returning: result)
            self?.continuation = nil
            print("[Location] ✅ done, locationName=\(name)")
        }
    }

    func locationManager(
        _: CLLocationManager,
        didFailWithError error: Error
    ) {
        print("[Location] ❌ didFailWithError:", error.localizedDescription)
        continuation?.resume(returning: (nil, nil, nil))
        continuation = nil
    }
}
