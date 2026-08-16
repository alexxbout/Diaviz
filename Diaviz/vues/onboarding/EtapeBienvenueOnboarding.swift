//
//  EtapeBienvenueOnboarding.swift
//  diaviz
//

import SwiftUI
import UIKit

/// Écran d'ouverture de l'onboarding — icône de l'app, titre, court
/// texte descriptif, bouton « Démarrer ».
///
/// L'icône est lue directement depuis `CFBundleIcons` (pas d'asset
/// dupliqué à maintenir) : fonctionne quel que soit le format de
/// production de l'icône (asset catalog classique ou Icon Composer).
struct EtapeBienvenueOnboarding: View {

    let onDemarrer: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            iconeApp
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
                }

            VStack(spacing: 8) {
                Text("Diaviz")
                    .font(.largeTitle.weight(.bold))

                Text("Comprends tes propres patterns glycémiques, jour après jour.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            Spacer()

            Button("Démarrer", action: onDemarrer)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

            Text("4 étapes rapides · modifiable plus tard depuis le profil")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }

    /// Icône réelle de l'app, telle qu'installée — fallback SF Symbol
    /// si `CFBundleIcons` est absent (ex. contexte de preview).
    private var iconeApp: Image {
        if let icones = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let principale = icones["CFBundlePrimaryIcon"] as? [String: Any],
           let fichiers = principale["CFBundleIconFiles"] as? [String],
           let nom = fichiers.last,
           let image = UIImage(named: nom) {
            return Image(uiImage: image)
        }
        return Image(systemName: "app.fill")
    }
}

#if DEBUG
#Preview {
    EtapeBienvenueOnboarding {}
}
#endif
