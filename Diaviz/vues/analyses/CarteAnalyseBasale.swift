//
//  CarteAnalyseBasale.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

// MARK: - Verdict (4 états du badge)

/// Conclusion synthétique de l'analyse basale, telle qu'affichée par la
/// pill de statut sur la carte sommaire. Le détail (à quelle heure, de
/// combien) vit dans `DetailAnalyseBasaleVue` — la carte ne diffuse que
/// le verdict global.
///
/// Les deux états « hors cible » (`.tropHaute`, `.tropBasse`) partagent
/// volontairement le même libellé « À revoir » et la même couleur orange
/// pour que la carte sommaire ne suggère pas une direction de correction
/// — l'utilisateur doit ouvrir le détail pour savoir quoi ajuster.
enum VerdictBasale: Sendable, Equatable {

    /// Profil glycémique nocturne stable, basale calibrée.
    case adaptee

    /// Tendance haute sur la fenêtre analysée → ajustement à examiner.
    case tropHaute

    /// Tendance basse sur la fenêtre analysée → ajustement à examiner.
    case tropBasse

    /// Pas assez de nuits exploitables (capteur HS, données récentes).
    case donneesInsuffisantes
}

// MARK: - Résumé (données alimentant la carte)

/// Snapshot prêt à afficher pour la carte sommaire « Basale » de la
/// page Analyses. Forme volontairement plate et `Equatable` pour
/// faciliter les previews et piloter les animations SwiftUI.
struct AnalyseBasaleResume: Equatable, Sendable {

    let verdict: VerdictBasale

    /// Date de la dernière mise à jour de l'analyse — sert au libellé
    /// « Dernière analyse : hier / lundi ».
    let derniereAnalyse: Date

    /// Nombre de nuits intégrées dans le calcul — affiché à la place du
    /// libellé temporel quand le verdict est `.donneesInsuffisantes`.
    let nuitsAnalysees: Int
}

extension AnalyseBasaleResume {

    /// Mock par défaut — verdict tropHaute, dernière analyse hier,
    /// 14 nuits analysées. Aligné sur la spec.
    static var mockDefault: AnalyseBasaleResume {
        AnalyseBasaleResume(
            verdict: .tropHaute,
            derniereAnalyse: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now,
            nuitsAnalysees: 14
        )
    }

    static var mockAdaptee: AnalyseBasaleResume {
        AnalyseBasaleResume(
            verdict: .adaptee,
            derniereAnalyse: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now,
            nuitsAnalysees: 21
        )
    }

    static var mockDonneesInsuffisantes: AnalyseBasaleResume {
        AnalyseBasaleResume(
            verdict: .donneesInsuffisantes,
            derniereAnalyse: Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now,
            nuitsAnalysees: 2
        )
    }
}

// MARK: - Vue

/// Carte sommaire de l'analyse basale — pleine largeur, tappable,
/// poussant `DetailAnalyseBasaleVue` via `NavigationLink`.
///
/// La page Analyses est un sommaire : chaque carte est une porte
/// d'entrée vers une page dédiée. Pas de graphique ici — uniquement
/// l'identification de l'analyse (icône + titre), un badge verdict
/// proéminent, et la fraîcheur des données en colonne droite.
///
/// Traitement **hero** (radius `Radius.large`, icône cerclée 40pt,
/// titre `.title3.bold()`, badge `.subheadline`) pour donner du poids
/// à la première carte de la page Analyses et inviter au tap. Le
/// `surfaceCarte()` (radius `medium`) n'est pas utilisé ici car la
/// carte sommaire d'analyses se rapproche du langage hero des cartes
/// score/insights de l'accueil plus que des cartes standard.
struct CarteAnalyseBasale: View {

    let resume: AnalyseBasaleResume

    var body: some View {
        NavigationLink {
            // Charge le snapshot détaillé qui correspond au verdict du
            // résumé. La page de détail travaille toujours sur la fenêtre
            // clinique standard 14 nuits (cf. `kFenetreNuits`).
            DetailAnalyseBasaleVue(
                analyse: AnalyseBasaleServiceMock.charger(verdict: resume.verdict)
            )
        } label: {
            contenu
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(libelleAccessible)
        .accessibilityHint("Ouvre l'analyse détaillée de l'insuline basale")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Contenu de la carte

    private var contenu: some View {
        VStack(alignment: .leading, spacing: 12) {
            enTete
            piedDePage
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
    }

    // MARK: - Ligne 1 — icône cerclée + titre + chevron

    private var enTete: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                Image(systemName: "syringe.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            Text("Basale")
                .font(.title3.bold())
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.body)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Ligne 2 — badge verdict + fraîcheur des données

    private var piedDePage: some View {
        HStack(alignment: .center, spacing: 12) {
            badgeVerdict

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Dernière analyse : \(libelleDate(resume.derniereAnalyse))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(resume.nuitsAnalysees) nuits analysées")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Badge pill de verdict

    private var badgeVerdict: some View {
        Text(libelleBadge)
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(couleurBadge)
            .clipShape(Capsule(style: .continuous))
    }

    // MARK: - Dérivés du verdict

    private var libelleBadge: String {
        switch resume.verdict {
        case .adaptee:                return "Adaptée"
        case .tropHaute, .tropBasse:  return "À revoir"
        case .donneesInsuffisantes:   return "En cours"
        }
    }

    private var couleurBadge: Color {
        switch resume.verdict {
        case .adaptee:                return .green
        case .tropHaute, .tropBasse:  return .orange
        case .donneesInsuffisantes:   return .secondary
        }
    }

    // MARK: - Formatage de la fraîcheur

    /// Formatage relatif court : « hier », « mercredi », ou date courte
    /// au-delà de 6 jours.
    ///
    /// Locale forcée à `fr_FR` — l'app est mono-langue française, on ne
    /// veut pas que la locale système (par ex. simulateur anglais)
    /// fasse remonter « Wednesday » dans une carte autrement traduite.
    private func libelleDate(_ date: Date) -> String {
        let now = Date.now
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0

        if days == 0 {
            return "aujourd'hui"
        } else if days == 1 {
            return "hier"
        } else if days < 7 {
            // Jour de la semaine en toutes lettres (« mercredi »).
            return date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "fr_FR")))
        } else {
            return date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR")))
        }
    }

    // MARK: - Accessibilité

    private var libelleAccessible: String {
        let verdict: String
        switch resume.verdict {
        case .adaptee:                verdict = "verdict adaptée"
        case .tropHaute, .tropBasse:  verdict = "verdict à revoir"
        case .donneesInsuffisantes:   verdict = "données insuffisantes, analyse en cours"
        }
        let fraicheur = "Dernière analyse \(libelleDate(resume.derniereAnalyse))"
        let volume = "\(resume.nuitsAnalysees) nuits analysées"
        return "Analyse basale, \(verdict). \(fraicheur). \(volume)."
    }
}

// MARK: - Aperçus

#Preview("Basale - Adaptée") {
    NavigationStack {
        CarteAnalyseBasale(resume: .mockAdaptee)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
    }
}

#Preview("Basale - À revoir") {
    NavigationStack {
        CarteAnalyseBasale(resume: .mockDefault)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
    }
}

#Preview("Basale - Données insuffisantes") {
    NavigationStack {
        CarteAnalyseBasale(resume: .mockDonneesInsuffisantes)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
    }
}

#Preview("Basale - À revoir (sombre)") {
    NavigationStack {
        CarteAnalyseBasale(resume: .mockDefault)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
    }
    .preferredColorScheme(.dark)
}
