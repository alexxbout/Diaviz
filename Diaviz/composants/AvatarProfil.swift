//
//  AvatarProfil.swift
//  diaviz
//
//  Created by Alexandre on 21/06/2026.
//

import SwiftUI
import UIKit

/// Avatar circulaire du profil — affiche la **photo** de l'utilisateur
/// si elle est définie, sinon l'**initiale** du prénom (« ? » si vide).
///
/// Composant de présentation pur (aucune action), réutilisé par
/// `BoutonProfilAvatar` (en-tête des onglets) et `SectionPhotoProfil`
/// (sheet Profil) pour garantir un rendu identique à toutes les tailles.
struct AvatarProfil: View {

    /// Photo encodée (JPEG) — `nil` → fallback initiale.
    let photoData: Data?

    /// Prénom — seule sa première lettre sert au fallback.
    let prenom: String

    /// Diamètre du cercle. La taille de l'initiale en dérive (×0.42).
    var taille: CGFloat = 44

    var body: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Color.white)
                    .overlay {
                        Text(initiale)
                            .font(.system(size: taille * 0.42, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: taille, height: taille)
        .clipShape(Circle())
        // Liseré fin pour détacher l'avatar du fond — utile surtout pour
        // le cercle blanc du fallback sur un en-tête clair.
        .overlay {
            Circle().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
        }
    }

    /// Première lettre du prénom en majuscule, ou « ? » si vide.
    private var initiale: String {
        let trim = prenom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let premier = trim.first else { return "?" }
        return String(premier).uppercased()
    }
}

// MARK: - Aperçus

#Preview("Initiale") {
    AvatarProfil(photoData: nil, prenom: "Camille", taille: 96)
        .padding()
}

#Preview("Sans prénom") {
    AvatarProfil(photoData: nil, prenom: "", taille: 96)
        .padding()
}
