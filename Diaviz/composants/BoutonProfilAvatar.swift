//
//  BoutonProfilAvatar.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Avatar circulaire affichant l'initiale du prénom — bouton d'accès
/// à la sheet Profil depuis la barre de navigation de l'accueil.
///
/// Style App Store / Apple Music : cercle 32×32 sur fond `accentColor`,
/// initiale en blanc, gras 14pt. Si le prénom est vide (premier
/// démarrage), on affiche « ? » pour signaler qu'un setup est attendu.
struct BoutonProfilAvatar: View {

    /// Prénom courant — utilisé uniquement pour son premier caractère.
    /// Passé en paramètre plutôt que lu dans `@Environment` pour que
    /// le composant reste autonome et facile à prévisualiser.
    let prenom: String

    /// Action de tap — typiquement `afficherProfil = true` côté parent.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 32, height: 32)
                .overlay {
                    Text(initiale)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profil")
        .accessibilityHint("Touchez deux fois pour ouvrir vos paramètres")
    }

    /// Première lettre du prénom en majuscule, ou « ? » si le prénom
    /// est vide / uniquement composé d'espaces.
    private var initiale: String {
        let trim = prenom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let premier = trim.first else { return "?" }
        return String(premier).uppercased()
    }
}

// MARK: - Aperçus

#Preview("Avec prénom") {
    BoutonProfilAvatar(prenom: "Camille") {}
        .padding()
}

#Preview("Sans prénom") {
    BoutonProfilAvatar(prenom: "") {}
        .padding()
}
