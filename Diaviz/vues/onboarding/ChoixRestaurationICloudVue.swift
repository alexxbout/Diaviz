//
//  ChoixRestaurationICloudVue.swift
//  diaviz
//

import SwiftData
import SwiftUI

/// Écran affiché au premier lancement quand `AppTabVues` détecte des
/// données déjà présentes (localement ou en cours d'import CloudKit) sur le
/// compte iCloud de l'appareil, plutôt que de supposer un départ à zéro et
/// d'ouvrir directement l'onboarding par-dessus des données qui allaient de
/// toute façon arriver.
///
/// Même famille visuelle que `OnboardingVue` (fond plat, pas de Liquid
/// Glass).
///
/// « Récupérer » **attend réellement** que le profil arrive : l'import
/// CloudKit après une réinstallation se fait par lots et peut prendre bien
/// plus que quelques secondes — les premières données (glycémies, repas)
/// arrivent souvent avant la ligne profil. Fermer immédiatement laissait
/// l'utilisateur devant une app qui semblait n'avoir rien restauré. Aucune
/// API ne permet de forcer ou d'accélérer cet import (confirmé par Apple
/// DTS) : on sonde donc le store à intervalle régulier jusqu'à ce que le
/// profil apparaisse, ou jusqu'à expiration.
struct ChoixRestaurationICloudVue: View {

    /// Appelé quand la récupération est terminée (profil trouvé, ou
    /// l'utilisateur choisit de continuer sans attendre davantage).
    var onRecuperer: () -> Void

    /// Appelé une fois la suppression effectuée, pour que l'appelant
    /// enchaîne sur l'onboarding classique.
    var onRepartirDeZero: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(ProfilService.self) private var profilService

    @State private var afficherConfirmation = false
    @State private var etat: EtatRecuperation = .choix

    private enum EtatRecuperation {
        case choix
        case recuperationEnCours
        /// Attente épuisée sans profil — la sync continue en tâche de fond.
        case attenteEpuisee
    }

    /// Durée maximale d'attente active. Généreuse : un import initial
    /// CloudKit complet dépasse largement les quelques secondes, surtout
    /// avec un historique de glycémies conséquent.
    private let dureeMaxAttente: Duration = .seconds(90)

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "icloud.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text(titre)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            Spacer()

            boutons
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
        .background(Color(.systemGroupedBackground))
        // `alert` comme les autres confirmations destructives de l'app
        // (page Données) : décision binaire et irréversible, présentée de la
        // même façon partout.
        .alert("Repartir de zéro ?", isPresented: $afficherConfirmation) {
            Button("Annuler", role: .cancel) { }
            Button("Tout supprimer", role: .destructive) {
                repartirDeZero()
            }
        } message: {
            Text("""
            Repas, injections, activités sportives, resucrages, états, \
            médications et profil seront définitivement supprimés (sur cet \
            appareil et sur iCloud). Les glycémies sont conservées. \
            Action irréversible.
            """)
        }
    }

    // MARK: - Contenu selon l'état

    private var titre: String {
        switch etat {
        case .choix: "Données iCloud trouvées"
        case .recuperationEnCours: "Récupération en cours"
        case .attenteEpuisee: "Récupération plus longue que prévu"
        }
    }

    private var message: String {
        switch etat {
        case .choix:
            "Des données existent déjà sur iCloud pour ce compte — profil, repas, glycémies…"
        case .recuperationEnCours:
            "Téléchargement de vos données depuis iCloud. Gardez l'app ouverte, ça peut prendre un moment."
        case .attenteEpuisee:
            "Le téléchargement continue en arrière-plan. Vos données apparaîtront au fur et à mesure — vous pouvez entrer dans l'app dès maintenant."
        }
    }

    /// Deux emplacements de bouton toujours présents, dont le second garde
    /// sa place même quand il n'a rien à afficher (`hidden()`, pas de
    /// retrait du layout). Faire apparaître/disparaître des boutons entre
    /// les états faisait sauter la mise en page et laissait entrevoir des
    /// cadres à moitié dessinés pendant la transition.
    private var boutons: some View {
        VStack(spacing: 10) {
            Button {
                switch etat {
                case .choix: afficherConfirmation = true
                case .recuperationEnCours: break
                case .attenteEpuisee: onRecuperer()
                }
            } label: {
                Group {
                    switch etat {
                    case .choix:
                        Text("Repartir de zéro")
                    case .recuperationEnCours:
                        ProgressView()
                    case .attenteEpuisee:
                        Text("Continuer")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(etat == .choix ? .red : .accentColor)
            .foregroundStyle(.white)
            .controlSize(.large)
            .disabled(etat == .recuperationEnCours)

            Button {
                Task { await recuperer() }
            } label: {
                Text("Récupérer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(etat != .choix)
            .opacity(etat == .choix ? 1 : 0)
        }
    }

    // MARK: - Actions

    /// Sonde le store jusqu'à ce que le profil arrive d'iCloud. Chaque tour
    /// passe par `ProfilService.rafraichirDepuisCloudKit()`, qui ré-adopte
    /// la ligne canonique (un profil valide gagne toujours contre le
    /// brouillon local vide).
    private func recuperer() async {
        etat = .recuperationEnCours

        let echeance = ContinuousClock.now.advanced(by: dureeMaxAttente)
        while ContinuousClock.now < echeance {
            if profilService.rafraichirDepuisCloudKit() {
                onRecuperer()
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }

        // Rien après l'échéance : on ne bloque pas l'utilisateur davantage,
        // la synchronisation poursuit son travail de son côté.
        etat = .attenteEpuisee
    }

    /// Repart réellement de zéro : vide le local **et** la zone iCloud.
    ///
    /// Ne pas toucher à iCloud ici serait un piège — les données trouvées
    /// à l'instant redescendraient dès la synchronisation suivante, et
    /// l'utilisateur qui vient de demander à repartir de zéro les verrait
    /// réapparaître. Les suppressions passent par
    /// `SuppressionDonneesService` (objet par objet, jamais en batch, seule
    /// forme que CloudKit exporte).
    private func repartirDeZero() {
        Task {
            etat = .recuperationEnCours
            SuppressionDonneesService.supprimerTout(contexte: modelContext)
            // Échec ignoré volontairement : le local est déjà vide, et
            // l'onboarding doit démarrer quoi qu'il arrive côté réseau.
            try? await SyncICloudService.supprimerZone()
            profilService.reinitialiser()
            onRepartirDeZero()
        }
    }
}

#if DEBUG
#Preview {
    ChoixRestaurationICloudVue(onRecuperer: {}, onRepartirDeZero: {})
        .environment(ProfilService.mockComplet())
}
#endif
