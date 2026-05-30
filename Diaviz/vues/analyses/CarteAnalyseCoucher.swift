//
//  CarteAnalyseCoucher.swift
//  diaviz
//
//  Created by Alexandre on 30/05/2026.
//

import SwiftUI

// MARK: - Identité des sous-analyses

/// Les trois sous-analyses fusionnées dans la page « Analyse du coucher » :
/// B1 (tendance basale), B2 (glycémie au coucher), B3 (corrections du soir).
/// Porte le libellé et le SF Symbol affichés sur chaque ligne glance.
enum SousAnalyseCoucher: String, CaseIterable, Sendable {
    case basale
    case glycemie
    case corrections

    var titre: String {
        switch self {
        case .basale:       return "Tendance basale"
        case .glycemie:     return "Endormissement"
        case .corrections:  return "Corrections du soir"
        }
    }

    var icone: String {
        switch self {
        case .basale:       return "syringe.fill"
        case .glycemie:     return "bed.double.fill"
        case .corrections:  return "plusminus"
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

    /// Verdict B1 — sert à router vers le bon snapshot de détail
    /// (`AnalyseBasaleServiceMock.charger(verdict:)`) en attendant la page
    /// fusionnée. La ligne glance « Tendance basale » en dérive son affichage.
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

    let resume: ResumeAnalyseCoucher

    var body: some View {
        NavigationLink {
            // TODO: remplacer par la page fusionnée « Analyse du coucher »
            // une fois designée. En attendant, on ouvre le détail B1 existant.
            DetailAnalyseBasaleVue(
                analyse: AnalyseBasaleServiceMock.charger(verdict: resume.verdictBasale)
            )
        } label: {
            contenu
        }
        .buttonStyle(.plain)
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
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
    }

    // MARK: En-tête — icône cerclée + titre + chevron

    private var enTete: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.indigo.opacity(0.12))
                Image(systemName: "moon.zzz.fill")
                    .font(.title3)
                    .foregroundStyle(.indigo)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            Text("Analyse du coucher")
                .font(.title3.bold())
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.body)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
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
                .foregroundStyle(.indigo)
                .frame(width: 22)
                .accessibilityHidden(true)

            Text(section.sousAnalyse.titre)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            statut(section.etat)
        }
        .padding(.vertical, 10)
    }

    // MARK: Rendu de l'état (pill résultat / compteur collecte / en attente)

    @ViewBuilder
    private func statut(_ etat: EtatSousAnalyse) -> some View {
        switch etat {
        case let .resultat(libelle, ton):
            Text(libelle)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(couleur(ton))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(couleur(ton).opacity(0.15))
                .clipShape(Capsule(style: .continuous))

        case let .collecte(actuel, requis):
            Label("\(actuel)/\(requis)", systemImage: "hourglass")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

        case .enAttente:
            Text("En attente")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func couleur(_ ton: TonResultat) -> Color {
        switch ton {
        case .positif:   return .green
        case .attention: return .orange
        case .neutre:    return .secondary
        }
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
            return "\(section.sousAnalyse.titre) : \(etat)"
        }
        return (["Analyse du coucher."] + resumeSections).joined(separator: " ")
    }
}

// MARK: - Mocks

extension ResumeAnalyseCoucher {

    /// État courant typique : basale à revoir (nouveau verdict), hypos repérées
    /// à l'endormissement, B3 pas encore démarrée. Usage réel à quelques semaines.
    static var mockDefault: ResumeAnalyseCoucher {
        ResumeAnalyseCoucher(
            verdictBasale: .tropHaute,
            sections: [
                ResumeSousAnalyse(sousAnalyse: .basale,
                                  etat: .resultat(libelle: "À revoir", ton: .attention),
                                  aDuNouveau: true),
                ResumeSousAnalyse(sousAnalyse: .glycemie,
                                  etat: .resultat(libelle: "2 hypos", ton: .attention),
                                  aDuNouveau: false),
                ResumeSousAnalyse(sousAnalyse: .corrections,
                                  etat: .enAttente,
                                  aDuNouveau: false),
            ]
        )
    }

    /// État mature : les trois sous-analyses produisent un résultat.
    static var mockMature: ResumeAnalyseCoucher {
        ResumeAnalyseCoucher(
            verdictBasale: .adaptee,
            sections: [
                ResumeSousAnalyse(sousAnalyse: .basale,
                                  etat: .resultat(libelle: "Adaptée", ton: .positif),
                                  aDuNouveau: false),
                ResumeSousAnalyse(sousAnalyse: .glycemie,
                                  etat: .resultat(libelle: "Aucune récente", ton: .neutre),
                                  aDuNouveau: false),
                ResumeSousAnalyse(sousAnalyse: .corrections,
                                  etat: .collecte(actuel: 12, requis: 15),
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
                ResumeSousAnalyse(sousAnalyse: .glycemie,
                                  etat: .enAttente,
                                  aDuNouveau: false),
                ResumeSousAnalyse(sousAnalyse: .corrections,
                                  etat: .enAttente,
                                  aDuNouveau: false),
            ]
        )
    }
}

// MARK: - Aperçus

#Preview("Coucher - Défaut") {
    NavigationStack {
        CarteAnalyseCoucher(resume: .mockDefault)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
    }
}

#Preview("Coucher - Mature") {
    NavigationStack {
        CarteAnalyseCoucher(resume: .mockMature)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
    }
}

#Preview("Coucher - Débutant") {
    NavigationStack {
        CarteAnalyseCoucher(resume: .mockDebutant)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
    }
}

#Preview("Coucher - Mature (sombre)") {
    NavigationStack {
        CarteAnalyseCoucher(resume: .mockMature)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
    }
    .preferredColorScheme(.dark)
}
