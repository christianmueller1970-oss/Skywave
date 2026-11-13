import CoreLocation
import Foundation
import Observation

/// Dünne Hülle um CoreLocation für den Positionsdialog: Freigabe
/// anfragen, einen Fix holen, Fehler lesbar machen. Auf einem Mac
/// ohne GPS kommt die Position aus WLAN-/IP-Ortung — unterwegs ohne
/// Netz liefert der Dienst oft nichts; der Dialog zeigt das an.
@MainActor @Observable final class LocationProvider: NSObject, CLLocationManagerDelegate {
    struct Fix: Equatable, Sendable {
        let latitude: Double
        let longitude: Double
        let accuracyMeters: Double
        let timestamp: Date
    }

    private(set) var fix: Fix?
    private(set) var errorText: String?
    private(set) var isRequesting = false
    private(set) var status: CLAuthorizationStatus

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Fragt bei Bedarf die Freigabe an und holt dann einen Fix.
    func request() {
        errorText = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            isRequesting = true
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            errorText =
                String(localized: "Standortfreigabe für Skywave fehlt — Systemeinstellungen → Datenschutz → Ortungsdienste.")
        default:
            isRequesting = true
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.status = status
            guard self.isRequesting else { return }
            switch status {
            case .authorized, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                self.isRequesting = false
                self.errorText = String(localized: "Standortfreigabe abgelehnt.")
            default:
                break
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        // A negative horizontalAccuracy marks an invalid fix — never
        // report that as «± 0 m».
        guard let last = locations.last(where: { $0.horizontalAccuracy >= 0 }) else {
            Task { @MainActor in
                self.isRequesting = false
                self.errorText = String(localized: "Standortdienst lieferte keinen gültigen Fix — bitte erneut versuchen.")
            }
            return
        }
        let fix = Fix(
            latitude: last.coordinate.latitude, longitude: last.coordinate.longitude,
            accuracyMeters: last.horizontalAccuracy, timestamp: last.timestamp)
        Task { @MainActor in
            self.fix = fix
            self.isRequesting = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let text = error.localizedDescription
        Task { @MainActor in
            self.isRequesting = false
            self.errorText = String(localized: "Kein Standort: \(text)")
        }
    }
}
