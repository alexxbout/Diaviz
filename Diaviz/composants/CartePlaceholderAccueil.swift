//
//  CartePlaceholderAccueil.swift
//  diaviz
//

import SwiftUI

/// Encadré affiché à la place d'une section d'accueil qui n'a encore rien à
/// montrer — « les repas sortis de cible s'afficheront ici ».
///
/// Les sections concernées (tendances, repas à revoir, glucides, ratios) se
/// masquaient entièrement quand elles étaient vides : sur un compte neuf,
/// l'accueil se réduisait à une carte de score sans chiffre, sans dire ce que
/// la page allait contenir un jour. Le placeholder garde la structure de la
/// page stable entre le premier lancement et l'usage courant.
///
/// **Toujours factuel, jamais une consigne** : la carte dit ce qui s'affichera
/// et à quelle condition mesurable, jamais ce que l'utilisateur devrait faire
/// de ses données (voir CLAUDE.md — « pas de recommandations, seulement des
/// observations »). Seule exception admise, `action` : ouvrir un réglage de
/// l'app n'est pas un conseil thérapeutique.
///
/// Quand un seuil chiffré existe déjà côté calculateur (nuits analysées,
/// jours avec repas…), `progression` l'expose plutôt que de laisser une
/// phrase figée : « 3 nuits analysées sur 5 » se vérifie, « bientôt » non.
struct CartePlaceholderAccueil: View {

    /// Compteur vers un seuil déjà appliqué par un calculateur — jamais une
    /// estimation inventée pour l'affichage.
    struct Progression: Equatable {
        let actuel: Int
        let requis: Int
        /// Libellé complet du compteur, accordé par l'appelant qui seul connaît
        /// l'unité comptée (« 3 nuits analysées sur 5 »).
        let libelle: String

        /// Bornée à [0, 1] : un `actuel` au-delà du seuil ne doit pas déborder
        /// la barre (cas transitoire possible entre deux recalculs).
        var fraction: Double {
            guard requis > 0 else { return 0 }
            return min(1, max(0, Double(actuel) / Double(requis)))
        }
    }

    let icone: String
    let message: String
    var progression: Progression? = nil
    /// Bouton optionnel — libellé + action, typiquement l'ouverture d'un
    /// réglage manquant.
    var action: (libelle: String, executer: () -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icone)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let progression {
                        Text(progression.libelle)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 0)
            }

            if let progression {
                ProgressView(value: progression.fraction)
                    .progressViewStyle(.linear)
                    .tint(.secondary)
                    .accessibilityHidden(true)
            }

            if let action {
                Button(action.libelle, action: action.executer)
                    .font(.subheadline)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCarte()
        .accessibilityElement(children: .combine)
        .accessibilityLabel([message, progression?.libelle].compactMap { $0 }.joined(separator: ". "))
    }
}

// MARK: - Aperçus

#if DEBUG
private func _apercu<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
    ScrollView {
        VStack(spacing: 16, content: contenu)
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Les trois états") {
    _apercu {
        CartePlaceholderAccueil(
            icone: "chart.line.uptrend.xyaxis",
            message: "Les tendances de vos nuits et de vos repas s'afficheront ici."
        )
        CartePlaceholderAccueil(
            icone: "chart.line.uptrend.xyaxis",
            message: "Les tendances de vos nuits et de vos repas s'afficheront ici.",
            progression: .init(actuel: 3, requis: 5, libelle: "3 nuits analysées sur 5")
        )
        CartePlaceholderAccueil(
            icone: "slider.horizontal.3",
            message: "Aucun ratio configuré pour l'instant.",
            action: (libelle: "Ouvrir le profil", executer: {})
        )
    }
}

#Preview("Sombre") {
    _apercu {
        CartePlaceholderAccueil(
            icone: "fork.knife",
            message: "Les repas dont la glycémie est sortie de cible s'afficheront ici."
        )
        CartePlaceholderAccueil(
            icone: "chart.bar.xaxis",
            message: "La moyenne de glucides par jour s'affichera ici.",
            progression: .init(actuel: 2, requis: 3, libelle: "2 jours avec repas cette semaine sur 3")
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Texte agrandi") {
    _apercu {
        CartePlaceholderAccueil(
            icone: "chart.bar.xaxis",
            message: "La moyenne de glucides par jour s'affichera ici.",
            progression: .init(actuel: 2, requis: 3, libelle: "2 jours avec repas cette semaine sur 3"),
            action: (libelle: "Ouvrir le profil", executer: {})
        )
    }
    .environment(\.dynamicTypeSize, .accessibility2)
}
#endif
