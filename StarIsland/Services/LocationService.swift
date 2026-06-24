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
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<LocationResult, Never>?

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.delegate = self
    }

    // MARK: - Public API

    /// Returns the current place name and coordinates.
    ///
    /// - Important: Does **not** block — completion is called on the main
    ///   queue asynchronously. If the user denies location or it fails,
    ///   returns all `nil` values so saving can proceed.
    typealias LocationResult = (locationName: String?,
                                latitude: Double?,
                                longitude: Double?)

    func requestLocation() async -> LocationResult {
        await withCheckedContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(returning: (nil, nil, nil))
                return
            }
            self.continuation = continuation

            let status = manager.authorizationStatus
            switch status {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
                // Delegate will handle both auth change and location
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                continuation.resume(returning: (nil, nil, nil))
                self.continuation = nil
            @unknown default:
                continuation.resume(returning: (nil, nil, nil))
                self.continuation = nil
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus != .notDetermined {
            // Now we know the answer — request a location
            manager.requestLocation()
        }
    }

    func locationManager(
        _: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else {
            continuation?.resume(returning: (nil, nil, nil))
            continuation = nil
            return
        }

        // Reverse geocode on a background queue
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            let name: String? = {
                guard let mk = placemarks?.first else { return nil }
                // Prefer the locality (city/town name), fall back to thoroughfare
                return mk.locality ?? mk.name
            }()

            let result: LocationResult = (
                locationName: name,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )

            self?.continuation?.resume(returning: result)
            self?.continuation = nil
        }
    }

    func locationManager(
        _: CLLocationManager,
        didFailWithError _: Error
    ) {
        continuation?.resume(returning: (nil, nil, nil))
        continuation = nil
    }
}
