//
//  OnboardingVue.swift
//  diaviz
//

import SwiftUI

/// Les 5 écrans de l'onboarding, dans l'ordre. `bienvenue` n'entre pas
/// dans le décompte « Étape X sur 4 » affiché à l'utilisateur.
private enum EtapeOnboarding: Int, CaseIterable {
    case bienvenue, identite, poids, insuline, ratios
}

/// Flux d'onboarding — présenté en plein écran soit au premier
/// lancement (profil invalide, câblé depuis `AppTabVues`), soit à la
/// demande depuis le profil (« Revoir la configuration initiale »).
///
/// Chaque étape réutilise les composants Réglages existants
/// (`SectionPhotoProfil`, `SectionInsuline`, `SectionRatios`,
/// `SectionRatioCorrection`) sauf le poids, qui a sa propre saisie
/// (voir `EtapePoidsOnboarding`). Auto-save à chaque champ via
/// `ProfilService`, comme partout ailleurs dans l'app — la sortie
/// (bouton « Terminer », ou fermeture prématurée) n'est jamais
/// bloquée, seulement signalée si des champs requis manquent.
struct OnboardingVue: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(ProfilService.self) private var service

    @State private var etape: EtapeOnboarding = .bienvenue
    @State private var afficherAlerteIncomplet = false

    /// Compteur de déclenchement du retour haptique de fin de parcours —
    /// `.sensoryFeedback` a besoin d'une valeur qui change, pas d'un appel
    /// direct. Même pattern que `BoutonValiderRepas`.
    @State private var triggerTermine: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            if etape != .bienvenue {
                enTete
            }

            Group {
                switch etape {
                case .bienvenue:
                    EtapeBienvenueOnboarding { avancer() }
                case .identite:
                    EtapeIdentiteOnboarding()
                case .poids:
                    EtapePoidsOnboarding()
                case .insuline:
                    EtapeInsulineOnboarding()
                case .ratios:
                    EtapeRatiosOnboarding()
                }
            }
            .frame(maxHeight: .infinity)

            if etape != .bienvenue {
                boutons
            }
        }
        // Fond unique pour tout l'écran. Les étapes en `Form` masquent leur
        // propre fond (`.scrollContentBackground(.hidden)`) pour se poser
        // dessus : sans ça, le gris du `Form` grouped se retrouvait pris en
        // sandwich entre un en-tête et un pied de page restés blancs.
        .background(Color(.systemGroupedBackground))
        .animation(.easeInOut(duration: 0.25), value: etape)
        // Léger retour à chaque passage d'étape (avant comme arrière), et
        // retour de succès à la validation finale — cohérent avec les
        // `.sensoryFeedback` déjà en place ailleurs dans l'app.
        .sensoryFeedback(.selection, trigger: etape)
        .sensoryFeedback(.success, trigger: triggerTermine)
        .alert(
            "Profil incomplet",
            isPresented: $afficherAlerteIncomplet
        ) {
            Button("Continuer la saisie", role: .cancel) { }
            Button("Terminer quand même") { dismiss() }
        } message: {
            Text("""
            Certains champs requis ne sont pas renseignés. Vous \
            pouvez les compléter maintenant ou plus tard, depuis \
            le profil.
            """)
        }
    }

    // MARK: - En-tête (chevron retour + « Étape X sur 4 » + progression)

    private var enTete: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    reculer()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .opacity(peutReculer ? 1 : 0)
                .disabled(!peutReculer)

                Spacer()

                // « Passer » vit ici plutôt que sous le bouton principal :
                // en bas il se retrouvait juste sous « Suivant », deux
                // actions concurrentes collées. En top bar il reste
                // accessible sans jamais entrer en compétition avec l'action
                // principale. Rendu invisible (mais présent) sur la dernière
                // étape, où « Terminer » couvre déjà la sortie — ça garde
                // aussi le compteur d'étapes centré.
                Button("Passer", action: avancer)
                    .font(.subheadline.weight(.medium))
                    .opacity(etape == .ratios ? 0 : 1)
                    .disabled(etape == .ratios)
            }
            // Compteur en overlay, pas dans le flux du `HStack` : le chevron
            // et « Passer » n'ont pas la même largeur, un placement entre deux
            // `Spacer` le décalerait visiblement du centre de l'écran.
            .overlay {
                Text("Étape \(numeroEtape) sur \(nombreEtapes)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            ProgressView(value: Double(numeroEtape), total: Double(nombreEtapes))
                .padding(.horizontal, 20)

            // Titre porté ici plutôt que dans chaque étape : les étapes en
            // `Form` n'ont pas de place naturelle pour un grand titre, et le
            // sortir du scroll le garde visible pendant la saisie.
            VStack(alignment: .leading, spacing: 4) {
                Text(titreEtape)
                    .font(.title2.weight(.bold))
                Text(sousTitreEtape)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var titreEtape: String {
        switch etape {
        case .bienvenue: ""
        case .identite: "Comment tu t'appelles ?"
        case .poids: "Quel est ton poids ?"
        case .insuline: "Tes insulines"
        case .ratios: "Tes ratios"
        }
    }

    private var sousTitreEtape: String {
        switch etape {
        case .bienvenue: ""
        case .identite: "Sert à personnaliser l'app. Rien n'est partagé."
        case .poids: "Affine certains calculs de référence. Modifiable à tout moment."
        case .insuline: "Utilisé pour calculer l'insuline active (IOB)."
        case .ratios: "Ratio de base et correction. Les ratios sport se règlent plus tard."
        }
    }

    // MARK: - Boutons bas de page

    private var boutons: some View {
        // Action principale seule en bas — « Passer » est remonté en top bar
        // pour ne pas lui faire concurrence juste en dessous.
        Button(etape == .ratios ? "Terminer" : "Suivant") {
            if etape == .ratios {
                terminer()
            } else {
                avancer()
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    // MARK: - Navigation entre étapes

    private var numeroEtape: Int { etape.rawValue }
    private var nombreEtapes: Int { EtapeOnboarding.allCases.count - 1 }
    private var peutReculer: Bool { etape.rawValue > EtapeOnboarding.identite.rawValue }

    private func avancer() {
        guard let suivante = EtapeOnboarding(rawValue: etape.rawValue + 1) else { return }
        etape = suivante
    }

    private func reculer() {
        guard let precedente = EtapeOnboarding(rawValue: etape.rawValue - 1) else { return }
        etape = precedente
    }

    /// Même logique que `ProfilVue.tenterFermeture()` : on ne bloque
    /// jamais la sortie, on prévient juste si le profil est incomplet.
    private func terminer() {
        if service.profil.estValide {
            triggerTermine += 1
            dismiss()
        } else {
            afficherAlerteIncomplet = true
        }
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview("Premier lancement") {
    OnboardingVue()
        .environment(ProfilService.mockVide())
}

#Preview("Profil déjà rempli (revisite)") {
    OnboardingVue()
        .environment(ProfilService.mockComplet())
}
#endif
