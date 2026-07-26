//
//  ScannerCodeBarresVue.swift
//  diaviz
//
//  Created by Alexandre on 26/07/2026.
//

import SwiftUI
import VisionKit
import Vision

/// Scanner de code-barres plein écran, basé sur `DataScannerViewController`
/// (VisionKit) — UI de scan native (viseur, mise au point), pas de code
/// AVFoundation bas niveau à maintenir.
///
/// Scan **unique** : le premier code-barres reconnu est remonté au parent via
/// `onCodeDetecte`, qui ferme la sheet. Pas de mode continu — chaque scan
/// correspond à un aliment qu'on va configurer dans `DetailAlimentSheet`.
struct ScannerCodeBarresVue: UIViewControllerRepresentable {

    /// Callback appelé une seule fois, au premier code-barres reconnu.
    let onCodeDetecte: (String) -> Void

    /// Symbologies courantes sur les produits alimentaires. EAN-13 couvre la
    /// quasi-totalité des produits européens ; EAN-8 et UPC-E les emballages
    /// trop petits pour un EAN-13 complet.
    private static let symbologies: [VNBarcodeSymbology] = [.ean13, .ean8, .upce]

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: Self.symbologies)],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        try? uiViewController.startScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeDetecte: onCodeDetecte)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCodeDetecte: (String) -> Void
        /// Garde-fou anti double-déclenchement : VisionKit peut signaler
        /// plusieurs fois le même item avant que la sheet parente n'ait eu le
        /// temps de se fermer (arrêt du scan).
        private var dejaDetecte = false

        init(onCodeDetecte: @escaping (String) -> Void) {
            self.onCodeDetecte = onCodeDetecte
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !dejaDetecte, case .barcode(let barcode) = addedItems.first, let payload = barcode.payloadStringValue else { return }
            dejaDetecte = true
            dataScanner.stopScanning()
            onCodeDetecte(payload)
        }
    }
}

/// Vue de secours quand le scan n'est pas disponible sur l'appareil
/// (simulateur, device trop ancien, ou permission caméra refusée).
struct ScannerIndisponibleVue: View {
    let raison: String

    var body: some View {
        ContentUnavailableView(
            "Scanner indisponible",
            systemImage: "barcode.viewfinder",
            description: Text(raison)
        )
    }
}
