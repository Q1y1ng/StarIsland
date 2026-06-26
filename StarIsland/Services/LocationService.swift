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
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            if let error {
                let nsError = error as NSError
                print("[Location] reverse geocode – error: domain=\(nsError.domain) code=\(nsError.code) desc=\(nsError.localizedDescription)")
            }

            let name: String = {
                guard let mk = placemarks?.first else {
                    let lat = location.coordinate.latitude
                    let lng = location.coordinate.longitude
                    let fallback = String(format: "%.4f, %.4f", lat, lng)
                    print("[Location] reverse geocode – no placemarks, fallback to coords: \(fallback)")
                    return fallback
                }

                // Street-first priority (T4.7):
                // 1. Thoroughfare + subThoroughfare (street + number)
                // 2. Thoroughfare only (street, e.g. "长安中路")
                // 3. Sub-locality (neighborhood / 商圈, e.g. "小寨")
                // 4. Sub-administrative area + locality (district + city)
                // 5. Locality (city)
                // 6. POI / place name (last resort — avoid shop names)
                // 7. Coordinates

                // 1. Thoroughfare + subThoroughfare (e.g. "长安中路 118号")
                let subThoroughfare = mk.subThoroughfare.flatMap { $0.isEmpty ? nil : $0 }
                let thoroughfare = mk.thoroughfare.flatMap { $0.isEmpty ? nil : $0 }
                if let thr = thoroughfare, let sub = subThoroughfare {
                    let result = "\(thr) \(sub)"
                    print("[Location] reverse geocode – thoroughfare+sub: \(result)")
                    return result
                }

                // 2. Thoroughfare only (e.g. "长安中路")
                if let thr = thoroughfare {
                    print("[Location] reverse geocode – thoroughfare: \(thr)")
                    return thr
                }

                // 3. Sub-locality (neighborhood / 商圈, e.g. "小寨")
                let subLocality = mk.subLocality.flatMap { $0.isEmpty ? nil : $0 }
                if let sub = subLocality {
                    print("[Location] reverse geocode – subLocality: \(sub)")
                    return sub
                }

                // 4. Sub-administrative area + locality (e.g. "雁塔区 · 西安市")
                let subAdmin = mk.subAdministrativeArea.flatMap { $0.isEmpty ? nil : $0 }
                let locality = mk.locality.flatMap { $0.isEmpty ? nil : $0 }
                if let sub = subAdmin, let loc = locality {
                    let result = "\(sub) · \(loc)"
                    print("[Location] reverse geocode – subAdmin+locality: \(result)")
                    return result
                }

                // 5. Locality only (e.g. "西安市")
                if let loc = locality {
                    print("[Location] reverse geocode – locality: \(loc)")
                    return loc
                }

                // 6. POI / place name (avoid if possible — usually shop names)
                if let name = mk.name, !name.isEmpty {
                    print("[Location] reverse geocode – name(POI): \(name)")
                    return name
                }

                // 7. Coordinates
                let lat = location.coordinate.latitude
                let lng = location.coordinate.longitude
                let fallback = String(format: "%.4f, %.4f", lat, lng)
                print("[Location] reverse geocode – fallback to coords: \(fallback)")
                return fallback
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
        let nsError = error as NSError
        print("[Location] ❌ didFailWithError: domain=\(nsError.domain) code=\(nsError.code) desc=\(nsError.localizedDescription) userInfo=\(nsError.userInfo)")
        continuation?.resume(returning: (nil, nil, nil))
        continuation = nil
    }
}
