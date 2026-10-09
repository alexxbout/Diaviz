//
//  CarteAnalyseRatio.swift
//  diaviz
//

import SwiftUI

/// Carte accueil — état du mining R1 (`CalculRatioObserve`) **par moment**
/// (matin/midi/goûter/dîner) ou par « Tous les repas » en mode ratio unique.
///
/// Affiche un **verdict** par moment plutôt qu'une progression vers un seuil :
/// « ratio confirmé », « écart détecté », ou le taux brut quand il y a encore
/// peu de recul. Un compteur seul (`12/30`) n'apprenait rien sur ce que valait
/// le ratio, restait muet pendant des semaines, et ne disait pas non plus que
/// changer un ratio remet son historique à zéro — d'où l'état dédié « ratio
/// changé le … » qui rend ce reset visible.
///
/// Sans aucun ratio configuré, la carte n'est plus masquée non plus : elle
/// affiche un `CartePlaceholderAccueil` disant ce qui s'affichera ici, avec un
/// accès direct au profil — le seul état où la section dépend d'un réglage
/// manquant plutôt que d'un volume de données.
struct CarteAnalyseRatio: View {

    @Environment(AnalyseRatioService.self) private var analyseRatioService

    /// Ouvre la sheet de détail « Écart de ratio » quand non-nil.
    var onTap: (() -> Void)? = nil

    /// Ouvre le profil depuis l'état « aucun ratio configuré ». `nil` → le
    /// placeholder reste affiché sans bouton (la carte ne se masque plus).
    var onOuvrirProfil: (() -> Void)? = nil

    private var profil: ProfilUtilisateur { ProfilService.shared.profil }

    private var lignes: [LigneVerdictRatio] {
        let sections = analyseRatioService.analyse.sections
        func section(_ groupe: SectionRepas?) -> ObservationRatioSection? {
            sections.first { $0.groupe == groupe }
        }
        func dateChangement(_ groupe: SectionRepas?) -> Date? {
            guard let groupe else { return profil.datesChangementRatioEffectives.unique }
            return analyseRatioService.dateChangement(section: groupe, profil: profil)
        }

        switch profil.modeRatio {
        case .unique:
            guard let ratio = profil.ratioUnique else { return [] }
            return [LigneVerdictRatio(
                libelle: "Tous les repas", icone: "fork.knife", teinte: .accentColor, ratio: ratio,
                section: section(nil), dateChangementRatio: dateChangement(nil)
            )]

        case .parMoment:
            let m = profil.ratiosParMoment
            var resultat: [LigneVerdictRatio] = []
            if let ratio = m.petitDejeuner {
                resultat.append(.init(libelle: "Petit-déjeuner", icone: "sunrise.fill", teinte: .orange, ratio: ratio,
                                      section: section(.petitDejeuner), dateChangementRatio: dateChangement(.petitDejeuner)))
            }
            if let ratio = m.dejeuner {
                resultat.append(.init(libelle: "Déjeuner", icone: "sun.max.fill", teinte: .blue, ratio: ratio,
                                      section: section(.dejeuner), dateChangementRatio: dateChangement(.dejeuner)))
            }
            if let ratio = m.gouter {
                resultat.append(.init(libelle: "Goûter", icone: "cup.and.saucer.fill", teinte: .pink, ratio: ratio,
                                      section: section(.enCas), dateChangementRatio: dateChangement(.enCas)))
            }
            if let ratio = m.diner {
                // Dîner et Nuit partagent le même ratio configuré (voir
                // `InsightsService.ratioConfigure`) mais restent deux groupes
                // de mining distincts (heure réelle du repas). On garde la
                // section « Dîner » comme porteuse du verdict et on ajoute
                // l'effectif de « Nuit » au dénominateur affiché.
                resultat.append(.init(libelle: "Dîner", icone: "moon.stars.fill", teinte: .indigo, ratio: ratio,
                                      section: section(.diner), dateChangementRatio: dateChangement(.diner),
                                      effectifAdditionnel: section(.nuit)?.effectif ?? 0))
            }
            return resultat
        }
    }

    /// Jaune doré (« goldenrod »).
    fileprivate static let teinte = Color(red: 0.85, green: 0.65, blue: 0.13)

    var body: some View {
        if lignes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Repas dans le ratio")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)

                CartePlaceholderAccueil(
                    icone: "slider.horizontal.3",
                    message: "Aucun ratio configuré. Le résultat de vos ratios, moment par moment, s'affichera ici.",
                    action: onOuvrirProfil.map { (libelle: "Ouvrir le profil", executer: $0) }
                )
            }
        } else if let onTap {
            Button(action: onTap) { carte }
                .buttonStyle(.plain)
        } else {
            carte
        }
    }

    /// Même patron que `CarteChargeActivite` / `CarteGlucidesSemaine` : titre
    /// teinté + chevron **dans** la carte plutôt qu'un bouton texte externe —
    /// toute la carte est tappable, cohérente avec les deux autres cartes
    /// d'accueil qui poussent un détail.
    private var carte: some View {
        VStack(alignment: .leading, spacing: 16) {
            ligneTitre
            graphe
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCarte()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(labelAccessibilite)
    }

    private var ligneTitre: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Self.teinte)
            Text("Repas dans le ratio")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Self.teinte)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
    }

    /// Hauteur maximale de la zone de barres — une barre à 100 % l'atteint
    /// exactement, le reste est proportionnel.
    private static let hauteurGraphe: CGFloat = 80

    /// Largeur d'une colonne (barre + légende dessous) — fixe, pour que les
    /// colonnes restent alignées quel que soit le nombre de moments.
    /// Calibrée pour que 4 colonnes + espacements tiennent dans la largeur
    /// disponible de la carte sur un iPhone standard : à 78pt, 4 colonnes
    /// (408pt avec les espacements) dépassaient l'espace dispo une fois le
    /// padding de carte et la marge de page déduits — un contenu à largeur
    /// fixe non compressible forçait alors toute la page à s'élargir pour
    /// lui faire de la place, exactement comme le ferait un `ScrollView`
    /// horizontal non contraint.
    private static let largeurColonne: CGFloat = 68

    /// Un seul graphique en barres verticales unit les moments sur un même
    /// axe (0-100 % de repas réussis avec le ratio configuré) plutôt qu'une
    /// carte séparée par moment — la comparaison entre moments se lit d'un
    /// coup d'œil. Centré dans la carte (`Spacer` de part et d'autre) plutôt
    /// que collé à gauche. Chaque barre reprend la teinte du moment (même
    /// identité que l'icône) : sans couleur, les colonnes redeviennent
    /// indiscernables entre elles.
    private var graphe: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(lignes) { ligne in
                    colonne(ligne)
                        .frame(width: Self.largeurColonne)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func colonne(_ ligne: LigneVerdictRatio) -> some View {
        VStack(spacing: 6) {
            Text(ligne.tauxReussite.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ligne.teinte)
                .monospacedDigit()

            barre(ligne)

            Image(systemName: ligne.icone)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ligne.teinte)

            Text(libelleAbrege(ligne.libelle))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    /// Hauteur symbolique de la barre hachurée — sans donnée exploitable, une
    /// hauteur pleine (`hauteurGraphe`) dominait visuellement les barres
    /// pleines à côté, comme si l'absence de donnée pesait plus que les
    /// vrais taux mesurés. Une barre basse dit « rien à montrer » sans
    /// écraser le reste du graphique.
    private static let hauteurHachuree: CGFloat = 20

    /// Barre pleine, teintée, hauteur proportionnelle au taux — sauf quand
    /// aucune comparaison n'est possible (changement de ratio récent, ou
    /// aucun repas exploitable) : la hauteur ne représenterait alors rien,
    /// donc la barre reste basse et se distingue par un **motif hachuré**
    /// plutôt que par une hauteur trompeuse.
    @ViewBuilder
    private func barre(_ ligne: LigneVerdictRatio) -> some View {
        if let taux = ligne.tauxReussite {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(ligne.teinte)
                .opacity(ligne.etat.estAttenue ? 0.5 : 1)
                .frame(width: 28, height: max(6, Self.hauteurGraphe * CGFloat(taux / 100)))
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(ligne.teinte.opacity(0.12))
                .overlay(
                    MotifHachures(couleur: ligne.teinte)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                )
                .frame(width: 28, height: Self.hauteurHachuree)
        }
    }

    /// Libellés de moment raccourcis pour tenir sur une colonne de largeur
    /// fixe sans réduire la taille de police.
    private func libelleAbrege(_ libelle: String) -> String {
        libelle == "Petit-déjeuner" ? "Petit-déj" : libelle
    }

    private var labelAccessibilite: String {
        let details = lignes.map { "\($0.libelle), \($0.etat.detail)" }
        return (["Repas dans le ratio"] + details).joined(separator: ". ")
    }
}

// MARK: - Motif hachuré

/// Trame diagonale — dessine une barre « sans donnée exploitable » sans
/// mentir sur une hauteur qu'aucun chiffre ne justifie.
private struct MotifHachures: View {
    let couleur: Color

    var body: some View {
        Canvas { context, size in
            let pas: CGFloat = 6
            var x = -size.height
            while x < size.width {
                var trait = Path()
                trait.move(to: CGPoint(x: x, y: size.height))
                trait.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(trait, with: .color(couleur.opacity(0.55)), lineWidth: 2)
                x += pas
            }
        }
    }
}

// MARK: - Ligne et verdict

/// État affiché pour un moment — hiérarchisé du plus informatif au moins
/// informatif, jamais une dose à appliquer.
private enum EtatVerdictRatio {
    /// Un écart significatif est sorti du mining (`ObservationRatioSection.ecart`).
    case ecartDetecte(taux: Int, effectif: Int)
    /// Assez de tranches exploitables, aucune ne bat le ratio configuré.
    case ratioConfirme(bons: Int, effectif: Int)
    /// Des repas analysés, mais aucune tranche n'atteint `effectifMinimalBucket`
    /// — on montre le taux brut avec son dénominateur, sans conclure.
    case peuDeRecul(bons: Int, effectif: Int)
    /// Le ratio de ce moment a changé récemment : l'historique antérieur n'est
    /// plus comparable, le compteur est reparti de zéro.
    case ratioChange(date: Date, effectif: Int)
    /// Aucun repas exploitable pour ce moment.
    case aucuneDonnee

    var badge: (texte: String, couleur: Color)? {
        switch self {
        case .ecartDetecte:  return ("écart détecté", .blue)
        case .ratioConfirme: return ("ratio confirmé", .green)
        case .peuDeRecul, .ratioChange, .aucuneDonnee: return nil
        }
    }

    /// Barre atténuée quand le pourcentage affiché n'est pas encore fiable —
    /// trop peu de repas, ou historique remis à zéro par un changement de
    /// ratio récent. La barre reste affichée (même métrique partout), juste
    /// visuellement moins affirmée.
    var estAttenue: Bool {
        switch self {
        case .peuDeRecul, .ratioChange: return true
        case .ecartDetecte, .ratioConfirme, .aucuneDonnee: return false
        }
    }

    var detail: String {
        switch self {
        case .ecartDetecte(let taux, let effectif):
            return "\(taux) % de bons résultats hors de votre ratio, sur \(effectif) repas"
        case .ratioConfirme(let bons, let effectif):
            return "\(bons) bons sur \(effectif)"
        case .peuDeRecul(let bons, let effectif):
            return "\(bons) bons sur \(effectif) — peu de recul"
        case .ratioChange(let date, let effectif):
            let jour = date.formatted(.dateTime.day().month(.abbreviated))
            return effectif == 0
                ? "Ratio changé le \(jour), aucun repas depuis"
                : "Ratio changé le \(jour), \(effectif) repas depuis"
        case .aucuneDonnee:
            return "Pas encore de repas analysé"
        }
    }
}

/// Une ligne — un groupe (moment ou « Tous les repas ») et son état.
private struct LigneVerdictRatio: Identifiable {
    let libelle: String
    /// SF Symbol du moment de la journée — identité visuelle constante, elle
    /// ne dépend jamais du verdict (porté par le badge).
    let icone: String
    /// Couleur du moment, même logique que `icone`.
    let teinte: Color
    let ratio: Double
    let section: ObservationRatioSection?
    let dateChangementRatio: Date?
    /// Effectif d'un groupe de mining distinct partageant le même ratio
    /// configuré (cas « Nuit » rattaché à « Dîner »), ajouté au dénominateur.
    var effectifAdditionnel: Int = 0

    var id: String { libelle }

    var ratioAffiche: String { "1u/\(Int(ratio.rounded()))g" }

    private var effectif: Int { (section?.effectif ?? 0) + effectifAdditionnel }

    /// Pourcentage de repas réussis **avec le ratio actuellement configuré**
    /// — la même métrique quel que soit l'état, y compris quand un écart est
    /// détecté (le taux affiché reste celui du ratio en place, pas celui de
    /// la dose alternative qui a déclenché l'écart). `nil` sans repas
    /// exploitable, pour ne pas afficher un 0 % trompeur.
    var tauxReussite: Double? {
        guard effectif > 0 else { return nil }
        let bons = section?.entrees.filter { $0.verdict == .bon }.count ?? 0
        return Double(bons) / Double(effectif) * 100
    }

    var estEcartDetecte: Bool { section?.ecart != nil }

    /// Un changement de ratio n'est signalé que tant qu'il explique encore
    /// quelque chose : passé ce volume de repas, l'analyse a repris et le
    /// verdict redevient le sujet.
    private static let repasAvantOubliDuChangement = 5

    var etat: EtatVerdictRatio {
        let bons = section?.entrees.filter { $0.verdict == .bon }.count ?? 0

        if let date = dateChangementRatio, effectif < Self.repasAvantOubliDuChangement {
            return .ratioChange(date: date, effectif: effectif)
        }
        guard effectif > 0 else { return .aucuneDonnee }

        if let ecart = section?.ecart {
            return .ecartDetecte(taux: Int((ecart.tauxOptimal * 100).rounded()), effectif: effectif)
        }
        // `buckets` non vide = au moins une tranche a franchi
        // `effectifMinimalBucket`, donc la comparaison a réellement eu lieu.
        if section?.buckets.isEmpty == false {
            return .ratioConfirme(bons: bons, effectif: effectif)
        }
        return .peuDeRecul(bons: bons, effectif: effectif)
    }
}

// MARK: - Aperçu

#if DEBUG

/// Pose un profil de preview et, optionnellement, des dates de changement de
/// ratio. `ProfilService.shared` est isolé du vrai profil de l'iPhone dans le
/// process de preview — rien n'est écrit sur l'appareil.
@MainActor
private func _posarProfil(
    mode: ModeRatio = .parMoment,
    dates: DatesChangementRatio? = nil
) {
    ProfilService.shared.mettreAJour {
        $0.appliquer(depuis: ProfilUtilisateur(
            prenom: "Camille",
            poidsKg: 78,
            insulineRapide: .fiasp,
            insulineLente: .tresiba,
            dureeActionInsulineHeures: 3.5,
            modeRatio: mode,
            ratioUnique: mode == .unique ? 11 : nil,
            ratiosParMoment: mode == .unique
                ? RatiosParMoment()
                : RatiosParMoment(petitDejeuner: 8, dejeuner: 12, gouter: 15, diner: 10),
            ratioCorrection: 35,
            horairesRepas: HorairesRepas.defaut(),
            seuilsGlycemiques: SeuilsGlycemiques(),
            preferencesAvancees: PreferencesAvancees()
        ))
        $0.datesChangementRatio = dates
    }
}

/// Service réel alimenté par les repas synthétiques R1 — mêmes données que la
/// preview « App complète » d'`AppTabVues`.
@MainActor
private func _serviceReel() -> AnalyseRatioService {
    let service = AnalyseRatioService()
    service.recalculer(depuis: RepasService.echantillonsApercuR1())
    return service
}

/// Service vide — aucun repas exploité.
@MainActor
private func _serviceVide() -> AnalyseRatioService { AnalyseRatioService() }

/// Service alimenté par un lot ciblé : `n` repas d'un moment donné, dont
/// `bons` réussis, tous à la dose suggérée (donc dans la tranche « proche »).
/// Permet de forcer un état précis sans dépendre du jeu complet.
@MainActor
private func _serviceCible(_ lots: [(section: SectionRepas, bons: Int, total: Int)]) -> AnalyseRatioService {
    let cal = Calendar.current
    var repas: [Repas] = []
    for lot in lots {
        let heure: (h: Int, m: Int)
        let glucides: Int
        let ratio: Double
        switch lot.section {
        case .petitDejeuner: heure = (7, 30);  glucides = 50;  ratio = 8
        case .dejeuner:      heure = (12, 30); glucides = 100; ratio = 12
        case .enCas:         heure = (16, 30); glucides = 40;  ratio = 15
        case .diner, .nuit:  heure = (19, 30); glucides = 80;  ratio = 10
        }
        for i in 0..<lot.total {
            let jour = cal.date(byAdding: .day, value: -(60 + i), to: Date()) ?? Date()
            let date = cal.date(bySettingHour: heure.h, minute: heure.m, second: 0, of: jour) ?? jour
            repas.append(Repas(
                heure: date,
                aliments: [Aliment(emoji: "🍽", nom: "Repas type", quantite: 1, glucides: glucides, insuline: 0)],
                doseGlobale: Double(glucides) / ratio,
                verdictPersiste: i < lot.bons ? .bon : .mauvais,
                ratioEffectifPersiste: ratio
            ))
        }
    }
    let service = AnalyseRatioService()
    service.recalculer(depuis: repas)
    return service
}

@MainActor
private func carteApercu(_ service: AnalyseRatioService) -> some View {
    CarteAnalyseRatio(onTap: {})
        .padding()
        .background(Color(.systemGroupedBackground))
        .environment(service)
}

#if DEBUG
#Preview("Verdicts mixtes") {
    _posarProfil()
    return carteApercu(_serviceReel())
}

#Preview("Sombre") {
    _posarProfil()
    return carteApercu(_serviceReel())
        .preferredColorScheme(.dark)
}

#Preview("Aucune donnée") {
    _posarProfil()
    return carteApercu(_serviceVide())
}

#Preview("Ratio unique") {
    _posarProfil(mode: .unique)
    return carteApercu(_serviceCible([(.dejeuner, 18, 26)]))
}

#Preview("Ratio confirmé partout") {
    _posarProfil()
    return carteApercu(_serviceCible([
        (.petitDejeuner, 14, 18), (.dejeuner, 22, 28), (.enCas, 9, 12), (.diner, 16, 20),
    ]))
}

#Preview("Peu de recul (sous 5 par tranche)") {
    _posarProfil()
    return carteApercu(_serviceCible([
        (.petitDejeuner, 2, 3), (.dejeuner, 3, 4), (.enCas, 1, 2), (.diner, 2, 2),
    ]))
}

#Preview("Ratios changés récemment") {
    _posarProfil(dates: DatesChangementRatio(
        unique: nil,
        petitDejeuner: Calendar.current.date(byAdding: .day, value: -4, to: Date()),
        dejeuner: Calendar.current.date(byAdding: .day, value: -12, to: Date()),
        gouter: nil,
        diner: Calendar.current.date(byAdding: .day, value: -2, to: Date())
    ))
    return carteApercu(_serviceCible([(.enCas, 8, 11)]))
}

#Preview("Un seul moment configuré") {
    ProfilService.shared.mettreAJour {
        $0.appliquer(depuis: ProfilUtilisateur(
            prenom: "Camille", poidsKg: 78,
            insulineRapide: .fiasp, insulineLente: .tresiba,
            dureeActionInsulineHeures: 3.5, modeRatio: .parMoment, ratioUnique: nil,
            ratiosParMoment: RatiosParMoment(dejeuner: 12),
            ratioCorrection: 35, horairesRepas: HorairesRepas.defaut(),
            seuilsGlycemiques: SeuilsGlycemiques(), preferencesAvancees: PreferencesAvancees()
        ))
    }
    return carteApercu(_serviceCible([(.dejeuner, 20, 27)]))
}

#Preview("Sans action au tap") {
    _posarProfil()
    return CarteAnalyseRatio()
        .padding()
        .background(Color(.systemGroupedBackground))
        .environment(_serviceReel())
}

#Preview("Texte agrandi") {
    _posarProfil()
    return carteApercu(_serviceReel())
        .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("Aucun ratio configuré (placeholder)") {
    ProfilService.shared.mettreAJour { $0.appliquer(depuis: .parDefaut()) }
    return CarteAnalyseRatio(onTap: {}, onOuvrirProfil: {})
        .padding()
        .background(Color(.systemGroupedBackground))
        .environment(_serviceVide())
}
#endif
#endif
