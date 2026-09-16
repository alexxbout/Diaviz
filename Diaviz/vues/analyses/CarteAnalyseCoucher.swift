//
//  CarteAnalyseCoucher.swift
//  diaviz
//
//  Created by Alexandre on 30/05/2026.
//

import SwiftUI

// MARK: - Identité des sous-analyses

/// Les deux sous-analyses fusionnées dans la page « Analyse du coucher » :
/// B1 (tendance basale) et « Hypos au coucher » (fusion B2 endormissement +
/// B3 corrections, focus hypo). Porte le libellé et le SF Symbol affichés
/// sur chaque ligne glance.
enum SousAnalyseCoucher: String, CaseIterable, Sendable {
    case basale
    case hyposCoucher

    var titre: String {
        switch self {
        case .basale:        return "Tendance basale"
        case .hyposCoucher:  return "Hypos au coucher"
        }
    }

    var icone: String {
        switch self {
        case .basale:        return "syringe.fill"
        case .hyposCoucher:  return "bed.double.fill"
        }
    }

    /// Couleur d'accent propre à la section — teinte l'icône et le titre des
    /// pills de la page « Analyse du coucher ».
    var couleur: Color {
        switch self {
        case .basale:        return .indigo
        case .hyposCoucher:  return .teal
        }
    }
}

// MARK: - État glance d'une sous-analyse

/// Ton du résultat affiché — pilote la couleur de la pill. Trois sous-analyses
/// aux horizons de données différents (B1 = 14j, B2 = 30j, B3 = 60j)
/// partagent ce vocabulaire d'affichage minimal.
enum TonResultat: Sendable, Equatable {
    case positif    // vert — basale adaptée, zone identifiée
    case attention  // orange — à revoir
    case neutre     // gris — neutre / informatif
}

/// État d'une sous-analyse tel qu'affiché en glance sur la carte sommaire.
///
/// `collecte` est un état de **première classe**, pas un fallback : B3 passe
/// des semaines à accumuler des soirées (15 min) avant de produire un verdict,
/// et B1 attend ses premières nuits valides. La carte assume ces compteurs au
/// lieu de paraître cassée. B2, lui, ne se gate pas : il remonte des faits
/// (hypos à l'endormissement) dès qu'ils surviennent, sans seuil amont.
enum EtatSousAnalyse: Equatable, Sendable {

    /// Résultat disponible (verdict B1, tranche optimale B2, pattern B3).
    case resultat(libelle: String, ton: TonResultat)

    /// Données en cours d'accumulation — `actuel` nuits/soirées sur `requis`.
    case collecte(actuel: Int, requis: Int)

    /// Pas encore démarrée (seuil amont non atteint, ex. B3 avant B2).
    case enAttente
}

/// Ligne glance : une sous-analyse + son état + un drapeau « du nouveau
/// depuis la dernière consultation ».
///
/// `aDuNouveau` est un signal délibérément concret, pas un recalcul permanent :
/// nouveau verdict (B1), tranche optimale qui change (B2), nouveau pattern (B3).
/// La carte ne fait que rendre le drapeau ; sa logique de déclenchement vit
/// dans la couche d'analyse.
struct ResumeSousAnalyse: Identifiable, Equatable, Sendable {
    var id: SousAnalyseCoucher { sousAnalyse }
    let sousAnalyse: SousAnalyseCoucher
    let etat: EtatSousAnalyse
    let aDuNouveau: Bool
}

// MARK: - Résumé alimentant la carte

/// Snapshot prêt à afficher pour la carte sommaire « Analyse du coucher ».
/// Forme plate et `Equatable` pour piloter previews et animations.
struct ResumeAnalyseCoucher: Equatable, Sendable {

    /// Verdict B1 — la ligne glance « Tendance basale » en dérive son affichage.
    let verdictBasale: VerdictBasale

    /// Les trois lignes glance, dans l'ordre vertical B1 → B2 → B3.
    let sections: [ResumeSousAnalyse]
}

// MARK: - Vue

/// Carte sommaire « Analyse du coucher » — pleine largeur, tappable, poussant
/// la page fusionnée (B1 + B2 + B3). Traitement **hero** (`Radius.large`,
/// icône cerclée 40pt) cohérent avec les cartes score/insights de l'accueil.
///
/// Trois lignes glance sous l'en-tête donnent un aperçu d'un coup d'œil de
/// l'état de chaque sous-analyse + un point « nouveau ». Les lignes ne sont
/// pas tappables individuellement en V1 : toute la carte ouvre la page.
struct CarteAnalyseCoucher: View {

    /// Accent violet de la carte — teinte le verre, le badge d'icône et les
    /// icônes des lignes glance.
    private static let accent = Color.indigo

    let resume: ResumeAnalyseCoucher

    /// Analyses réelles (calculées depuis le hub), transmises telles quelles à
    /// la page de détail. Volontairement **non optionnelles** : un fallback vers
    /// un snapshot mocké ferait afficher un faux constat sur un écran de suivi
    /// de santé si l'appelant oubliait de les fournir. Les previews passent
    /// explicitement leurs fixtures.
    var analyse: AnalyseBasaleDetail
    var endormissement: AnalyseEndormissement
    var corrections: AnalyseCorrections

    /// `true` pendant le recalcul des 3 analyses — remplace le chevron par un
    /// spinner (la carte reste tappable, elle ouvre les données déjà connues).
    var chargement: Bool = false

    /// Appelé quand le détail s'ouvre réellement (pas juste au survol de
    /// cette carte), avec le snapshot `AnalyseBasaleDetail` **affiché** par
    /// la page — le parent y marque ce verdict précis comme vu, ce qui
    /// efface le badge de l'onglet Analyses.
    var onOuvrirDetail: ((AnalyseBasaleDetail) -> Void)? = nil

    var body: some View {
        NavigationLink {
            DetailAnalyseBasaleVue(
                analyse: analyse,
                endormissement: endormissement,
                corrections: corrections,
                onApparition: onOuvrirDetail
            )
        } label: {
            contenu
        }
        .buttonStyle(.plain)
        // `.shadow`/`.compositingGroup` doivent vivre **ici**, hors du
        // `label:` du `NavigationLink` — appliqués dedans (sur `contenu`),
        // le système de rendu du bouton rognait l'ombre aux bornes du
        // label et elle ne s'affichait jamais, quels que soient rayon et
        // opacité. Même correctif que `JournalVue` pour `CarteSection`.
        .compositingGroup()
        .shadow(color: Self.accent.opacity(0.45), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(libelleAccessible)
        .accessibilityHint("Ouvre l'analyse détaillée du coucher")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Contenu

    private var contenu: some View {
        VStack(alignment: .leading, spacing: 14) {
            enTete
            lignes
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Fond opaque teinté violet — plus de Liquid Glass (carte de
        // contenu, pas un élément flottant, voir skill `liquid-glass`).
        // L'ombre vit hors du `NavigationLink` (voir `body`), pas ici.
        .surfaceCarte(fond: Self.accent.opacity(0.10))
    }

    // MARK: En-tête — icône cerclée + titre + chevron

    private var enTete: some View {
        HStack(spacing: 12) {
            // Badge plein en dégradé : sur un fond de verre teinté, un cercle
            // à faible opacité disparaîtrait — il faut un contraste franc.
            ZStack {
                Circle().fill(
                    LinearGradient(
                        colors: [Self.accent, Self.accent.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                Image(systemName: "moon.zzz.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            Text("Analyse du coucher")
                .font(.title3.bold())
                .foregroundStyle(.primary)

            Spacer()

            if chargement {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: Lignes glance des sous-analyses

    private var lignes: some View {
        VStack(spacing: 0) {
            ForEach(Array(resume.sections.enumerated()), id: \.element.id) { index, section in
                if index > 0 {
                    Divider().padding(.leading, 34)
                }
                ligne(section)
            }
        }
    }

    @ViewBuilder
    private func ligne(_ section: ResumeSousAnalyse) -> some View {
        HStack(spacing: 12) {
            Image(systemName: section.sousAnalyse.icone)
                .font(.subheadline)
                .foregroundStyle(Self.accent)
                .frame(width: 22)
                .accessibilityHidden(true)

            Text(section.sousAnalyse.titre)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            if section.aDuNouveau {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 8)

            StatutSousAnalyseVue(etat: section.etat)
        }
        .padding(.vertical, 10)
    }

    // MARK: Accessibilité

    private var libelleAccessible: String {
        let resumeSections = resume.sections.map { section -> String in
            let etat: String
            switch section.etat {
            case let .resultat(libelle, _): etat = libelle
            case let .collecte(actuel, requis): etat = "en cours, \(actuel) sur \(requis)"
            case .enAttente: etat = "en attente"
            }
            let suffixeNouveau = section.aDuNouveau ? ", nouveau" : ""
            return "\(section.sousAnalyse.titre) : \(etat)\(suffixeNouveau)"
        }
        return (["Analyse du coucher."] + resumeSections).joined(separator: " ")
    }
}

// MARK: - Mocks

extension ResumeAnalyseCoucher {

    /// État courant typique : basale à revoir (nouveau verdict), hypos repérées
    /// au coucher. Usage réel à quelques semaines.
    static var mockDefault: ResumeAnalyseCoucher {
        ResumeAnalyseCoucher(
            verdictBasale: .tropHaute,
            sections: [
                ResumeSousAnalyse(sousAnalyse: .basale,
                                  etat: .resultat(libelle: "À revoir", ton: .attention),
                                  aDuNouveau: true),
                ResumeSousAnalyse(sousAnalyse: .hyposCoucher,
                                  etat: .resultat(libelle: "2 hypos", ton: .attention),
                                  aDuNouveau: false),
            ]
        )
    }

    /// État mature : les deux sous-analyses produisent un résultat.
    static var mockMature: ResumeAnalyseCoucher {
        ResumeAnalyseCoucher(
            verdictBasale: .adaptee,
            sections: [
                ResumeSousAnalyse(sousAnalyse: .basale,
                                  etat: .resultat(libelle: "Adaptée", ton: .positif),
                                  aDuNouveau: false),
                ResumeSousAnalyse(sousAnalyse: .hyposCoucher,
                                  etat: .resultat(libelle: "Aucune récente", ton: .neutre),
                                  aDuNouveau: false),
            ]
        )
    }

    /// Début d'usage : peu de données, tout en collecte ou en attente.
    static var mockDebutant: ResumeAnalyseCoucher {
        ResumeAnalyseCoucher(
            verdictBasale: .donneesInsuffisantes,
            sections: [
                ResumeSousAnalyse(sousAnalyse: .basale,
                                  etat: .collecte(actuel: 2, requis: 3),
                                  aDuNouveau: false),
                ResumeSousAnalyse(sousAnalyse: .hyposCoucher,
                                  etat: .enAttente,
                                  aDuNouveau: false),
            ]
        )
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview("Coucher - Défaut") {
    NavigationStack {
        CarteAnalyseCoucher(
            resume: .mockDefault,
            analyse: AnalyseBasaleServiceMock.charger(verdict: ResumeAnalyseCoucher.mockDefault.verdictBasale),
            endormissement: .mock,
            corrections: .mock
        )
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
    }
}

#Preview("Coucher - Mature") {
    NavigationStack {
        CarteAnalyseCoucher(
            resume: .mockMature,
            analyse: AnalyseBasaleServiceMock.charger(verdict: ResumeAnalyseCoucher.mockMature.verdictBasale),
            endormissement: .mock,
            corrections: .mock
        )
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
    }
}

#Preview("Coucher - Débutant") {
    NavigationStack {
        CarteAnalyseCoucher(
            resume: .mockDebutant,
            analyse: AnalyseBasaleServiceMock.charger(verdict: ResumeAnalyseCoucher.mockDebutant.verdictBasale),
            endormissement: .mock,
            corrections: .mock
        )
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
    }
}

#Preview("Coucher - Mature (sombre)") {
    NavigationStack {
        CarteAnalyseCoucher(
            resume: .mockMature,
            analyse: AnalyseBasaleServiceMock.charger(verdict: ResumeAnalyseCoucher.mockMature.verdictBasale),
            endormissement: .mock,
            corrections: .mock
        )
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
    }
    .preferredColorScheme(.dark)
}
#endif
