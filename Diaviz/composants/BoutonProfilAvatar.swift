//
//  BoutonProfilAvatar.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Avatar circulaire **bouton** d'accès à la sheet Profil depuis
/// l'en-tête des onglets racines. Affiche la photo de profil si elle est
/// définie, sinon l'initiale du prénom — rendu délégué à `AvatarProfil`.
struct BoutonProfilAvatar: View {

    /// Prénom courant — pour le fallback initiale.
    let prenom: String

    /// Photo de profil encodée — `nil` → fallback initiale.
    let photoData: Data?

    /// Diamètre du cercle. 44pt par défaut : avatar bien visible et cible
    /// tactile conforme HIG (≥ 44×44).
    var taille: CGFloat = 44

    /// Action de tap — typiquement `afficherProfil = true` côté parent.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AvatarProfil(photoData: photoData, prenom: prenom, taille: taille)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profil")
        .accessibilityHint("Touchez deux fois pour ouvrir vos paramètres")
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview("Avec prénom") {
    BoutonProfilAvatar(prenom: "Camille", photoData: nil) {}
        .padding()
}

#Preview("Sans prénom") {
    BoutonProfilAvatar(prenom: "", photoData: nil) {}
        .padding()
}
#endif
