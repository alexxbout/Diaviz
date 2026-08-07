//
//  FriseSeanceSportive.swift
//  diaviz
//

import Charts
import SwiftUI

/// Courbe glycémique **parcourable au doigt** d'une séance sportive, doublée
/// de la liste complète des événements survenus autour de l'effort.
///
/// Les deux moitiés se répondent : faire glisser le curseur met en évidence
/// l'événement le plus proche dans la liste, taper une ligne de la liste
/// déplace le curseur. C'est ce couplage qui règle le problème de densité —
/// la courbe ne porte que de discrets points (illisibles au-delà de quelques
/// événements si on y collait des libellés), la liste porte tout le détail
/// sans troncature ni chevauchement, quel qu'en soit le nombre.
///
/// Au repos (aucun curseur posé), le panneau affiche le bilan de la séance
/// plutôt qu'un instant arbitraire : l'écran reste lisible d'un coup d'œil
/// sans avoir à interagir.
struct FriseSeanceSportive: View {

    let reponse: ReponseGlycemiqueSport
    let activite: ActiviteSportive
    let evenements: [EvenementActivite]

    /// Instant survolé, en secondes depuis le début de l'activité. `nil`
    /// quand le doigt n'est pas posé — on affiche alors le bilan.
    @State private var tempsCurseur: TimeInterval?
    /// Événement actuellement mis en évidence (aimantation ou tap liste).
    @State private var evenementActif: String?
    /// Ligne dont l'encart de résultat est déplié. Distinct d'`evenementActif` :
    /// le curseur met en évidence, seul le tap déplie (sinon la mise en page
    /// sauterait à chaque déplacement du doigt sur la courbe).
    @State private var ligneDepliee: String?
    @State private var afficherExplication = false

    /// Distance d'aimantation du curseur sur un événement.
    private static let seuilAimantation: TimeInterval = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Barre de contexte **au-dessus** de la courbe : pendant un
            // scrub, le doigt masque tout ce qui est en dessous du point
            // touché — la lecture doit rester dégagée.
            barreContexte
            courbe
            if !lignesListe.isEmpty {
                liste
                if aDesVerdicts {
                    boutonExplication
                }
            }
        }
        .sheet(isPresented: $afficherExplication) {
            SheetExplicativeVerdictsResucrage()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    /// N'apparaît que si au moins un resucrage a été jugé — inutile de
    /// proposer d'expliquer des verdicts absents.
    private var aDesVerdicts: Bool {
        evenements.contains { $0.resultat != nil }
    }

    private var boutonExplication: some View {
        Button {
            afficherExplication = true
        } label: {
            Label("Comment un resucrage est jugé", systemImage: "info.circle")
                .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.leading, 4)
    }

    // MARK: - Courbe

    private var courbe: some View {
        Chart {
            zoneCible
            zoneEffort
            zonesPause
            ligneHypo
            ligneHyper
            courbeMarks
            pointsEvenements
            curseurMark
        }
        .chartXScale(domain: domaineX)
        .chartYScale(domain: domaineY)
        .chartXAxis { axeX }
        .chartYAxis { axeY }
        .chartPlotStyle { $0.padding(.top, 16).padding(.bottom, 6) }
        .frame(height: 220)
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plotFrame = proxy.plotFrame {
                    let rect = geo[plotFrame]
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(gestureScrub(proxy: proxy, rect: rect))
                }
            }
        }
        .sensoryFeedback(.selection, trigger: evenementActif)
        .accessibilityElement()
        .accessibilityLabel("Courbe glycémique de la séance, \(evenements.count) événements")
    }

    /// Glisser (ou toucher) pose le curseur ; relâcher le retire, ce qui
    /// ramène le panneau au bilan de la séance.
    private func gestureScrub(proxy: ChartProxy, rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { valeur in
                let x = valeur.location.x - rect.minX
                guard let brut: TimeInterval = proxy.value(atX: x) else { return }
                let borne = min(max(brut, domaineX.lowerBound), domaineX.upperBound)
                // Aimantation : si un événement est assez proche, on s'y colle
                // — sinon le curseur suit librement le doigt.
                if let proche = evenementLePlusProche(de: borne),
                   abs(tempsDe(proche) - borne) <= Self.seuilAimantation {
                    tempsCurseur = tempsDe(proche)
                    if evenementActif != proche.id { evenementActif = proche.id }
                } else {
                    tempsCurseur = borne
                    if evenementActif != nil { evenementActif = nil }
                }
            }
            .onEnded { _ in
                tempsCurseur = nil
                evenementActif = nil
                // Un scrub reprend la main sur la lecture : on referme l'encart
                // ouvert au tap, sinon il resterait ouvert sur une ligne qui
                // n'est plus celle qu'on regarde.
                ligneDepliee = nil
            }
    }

    // MARK: - Contenus du graphique

    @ChartContentBuilder
    private var zoneCible: some ChartContent {
        RectangleMark(
            xStart: .value("Début", domaineX.lowerBound),
            xEnd: .value("Fin", domaineX.upperBound),
            yStart: .value("Cible bas", seuils.hypoglycemie),
            yEnd: .value("Cible haut", seuils.hyperglycemie)
        )
        .foregroundStyle(.green.opacity(0.08))
    }

    @ChartContentBuilder
    private var zoneEffort: some ChartContent {
        RectangleMark(
            xStart: .value("Début effort", 0),
            xEnd: .value("Fin effort", dureeEffortSec),
            yStart: .value("Y bas", domaineY.lowerBound),
            yEnd: .value("Y haut", domaineY.upperBound)
        )
        .foregroundStyle(.blue.opacity(0.06))
    }

    /// Bandes grises sur les fenêtres de pause — disponibles depuis que la
    /// séance live les persiste.
    @ChartContentBuilder
    private var zonesPause: some ChartContent {
        ForEach(Array(activite.pauses.enumerated()), id: \.offset) { _, pause in
            RectangleMark(
                xStart: .value("Début pause", pause.debut.timeIntervalSince(activite.dateDebut)),
                xEnd: .value("Fin pause", pause.fin.timeIntervalSince(activite.dateDebut)),
                yStart: .value("Y bas", domaineY.lowerBound),
                yEnd: .value("Y haut", domaineY.upperBound)
            )
            .foregroundStyle(.gray.opacity(0.18))
        }
    }

    @ChartContentBuilder
    private var ligneHypo: some ChartContent {
        RuleMark(y: .value("Hypo", seuils.hypoglycemie))
            .foregroundStyle(.red.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    @ChartContentBuilder
    private var ligneHyper: some ChartContent {
        RuleMark(y: .value("Hyper", seuils.hyperglycemie))
            .foregroundStyle(.orange.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    @ChartContentBuilder
    private var courbeMarks: some ChartContent {
        ForEach(points) { point in
            LineMark(
                x: .value("Temps", point.temps),
                y: .value("Glycémie", point.valeur)
            )
            .foregroundStyle(couleurCourbe)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.catmullRom)
        }
    }

    /// Points d'événements : volontairement discrets et sans libellé — c'est
    /// la liste qui nomme. Le point actif grossit et prend un halo.
    @ChartContentBuilder
    private var pointsEvenements: some ChartContent {
        ForEach(evenementsDansFenetre) { evenement in
            let temps = tempsDe(evenement)
            PointMark(
                x: .value("Temps", temps),
                y: .value("Glycémie", glycemie(a: temps))
            )
            .symbol {
                Circle()
                    .fill(evenement.couleur)
                    .frame(
                        width: evenement.id == evenementActif ? 13 : 8,
                        height: evenement.id == evenementActif ? 13 : 8
                    )
                    .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                    .animation(.spring(response: 0.25), value: evenementActif)
            }
        }
    }

    @ChartContentBuilder
    private var curseurMark: some ChartContent {
        if let tempsCurseur {
            RuleMark(x: .value("Curseur", tempsCurseur))
                .foregroundStyle(couleurCurseur.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1.5))

            PointMark(
                x: .value("Curseur", tempsCurseur),
                y: .value("Glycémie", glycemie(a: tempsCurseur))
            )
            .symbol {
                Circle()
                    .fill(couleurCurseur)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().strokeBorder(.background, lineWidth: 2))
            }
        }
    }

    private var axeX: some AxisContent {
        AxisMarks(values: xMarques) { valeur in
            AxisGridLine()
            AxisTick()
            AxisValueLabel {
                if let t = valeur.as(TimeInterval.self) {
                    Text(labelTemps(t)).font(.caption2)
                }
            }
        }
    }

    private var axeY: some AxisContent {
        AxisMarks(position: .trailing, values: yMarques) { valeur in
            AxisGridLine()
            AxisTick()
            AxisValueLabel {
                if let v = valeur.as(Double.self) {
                    Text("\(Int(v))").font(.caption2).monospacedDigit()
                }
            }
        }
    }

    // MARK: - Barre de contexte
    //
    // Une seule ligne, hauteur fixe (pas de saut de mise en page au passage
    // d'un état à l'autre). Curseur posé → l'instant survolé. Sinon → bilan
    // de la séance, pour que l'écran reste informatif sans interaction.
    //
    // Le détail complet d'un événement reste dans la liste du bas : ici on
    // ne garde que ce qu'on veut lire *pendant* qu'on fait glisser le doigt.

    private var barreContexte: some View {
        HStack(spacing: 8) {
            if let tempsCurseur {
                contenuInstant(tempsCurseur)
            } else {
                contenuBilan
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            .regular.tint(couleurFondBarre),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    @ViewBuilder
    private func contenuInstant(_ temps: TimeInterval) -> some View {
        let evenement = evenements.first { $0.id == evenementActif }

        if let evenement {
            Image(systemName: evenement.icone)
                .font(.footnote)
                .foregroundStyle(evenement.couleur)
        }

        Text(labelHorloge(temps))
            .font(.subheadline.weight(.medium))
            .monospacedDigit()

        Text(evenement?.titre ?? descriptionPhase(temps))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

        Spacer(minLength: 4)

        Text("\(Int(glycemie(a: temps).rounded()))")
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(couleurGlycemie(glycemie(a: temps)))
    }

    @ViewBuilder
    private var contenuBilan: some View {
        Text("Sur l'effort")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        Spacer(minLength: 4)
        Text("\(Int(reponse.glycemieDebut)) → \(Int(reponse.glycemieFin))")
            .font(.subheadline.weight(.medium))
            .monospacedDigit()
        Text(deltaFormate)
            .font(.subheadline.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(couleurCourbe)
    }

    /// Teinte du verre de la barre — prend la couleur de l'événement
    /// sélectionné, transparente sinon. Même comportement que la barre de
    /// contexte de la sheet « Détail d'une soirée ».
    private var couleurFondBarre: Color {
        guard let evenement = evenements.first(where: { $0.id == evenementActif }) else {
            return .clear
        }
        return evenement.couleur.opacity(0.16)
    }

    // MARK: - Liste

    private var liste: some View {
        VStack(spacing: 0) {
            ForEach(lignesListe) { ligne in
                ligneListe(ligne)
                if ligne.id != lignesListe.last?.id {
                    Divider().padding(.leading, 46)
                }
            }
        }
        .carteListeEvenements()
    }

    private func ligneListe(_ ligne: LigneFrise) -> some View {
        let resultat = evenements.first { $0.id == ligne.idEvenement }?.resultat
        return LigneEvenementCourbe(
            icone: ligne.icone,
            couleur: ligne.couleur,
            titre: ligne.titre,
            sousTitre: ligne.sousTitre,
            detail: ligne.detail,
            actif: ligne.idEvenement != nil && ligne.idEvenement == evenementActif,
            pastille: resultat.map {
                .init(
                    texte: $0.verdict.libelle,
                    couleur: $0.verdict.couleurTexte,
                    fond: $0.verdict.couleurFond
                )
            },
            encart: {
                // Déplié au tap seulement (`ligneDepliee`), jamais au passage
                // du curseur : la liste sauterait sous le doigt pendant qu'on
                // fait glisser la courbe.
                guard let resultat, ligne.id == ligneDepliee else { return nil }
                return AnyView(EncartResultatPrise(resultat: resultat))
            }
        )
        // Pas de `withAnimation` ici : il propagerait la transition à tout le
        // `Chart`, qui ré-interpole alors son tracé — la courbe repassait
        // visiblement par une version anguleuse avant de retrouver son lissage
        // `catmullRom`. Les seules choses qu'on veut animer (surbrillance de
        // la ligne, taille du point) portent leur propre `.animation(_:value:)`.
        .onTapGesture {
            guard let id = ligne.idEvenement,
                  let evenement = evenements.first(where: { $0.id == id }) else { return }
            if evenementActif == id {
                evenementActif = nil
                tempsCurseur = nil
                ligneDepliee = nil
            } else {
                evenementActif = id
                tempsCurseur = tempsDe(evenement)
                // Seul le tap déplie — et seulement s'il y a un résultat.
                ligneDepliee = evenement.resultat == nil ? nil : ligne.id
            }
        }
    }

    /// Lignes affichées : les aliments pré-sport d'abord (ils n'ont pas
    /// d'horodatage propre — ils appartiennent à l'activité, pas au hub —
    /// donc pas de marqueur sur la courbe, seulement une ligne de contexte),
    /// puis les événements corrélés dans l'ordre chronologique.
    private var lignesListe: [LigneFrise] {
        var lignes: [LigneFrise] = []

        if !activite.alimentsPreSport.isEmpty {
            let noms = activite.alimentsPreSport.map(\.nomAffiche).joined(separator: ", ")
            lignes.append(
                LigneFrise(
                    id: "pre-sport",
                    idEvenement: nil,
                    icone: "fork.knife",
                    couleur: .green,
                    titre: "Glucides pré-sport",
                    sousTitre: noms,
                    detail: "\(Int(activite.glucidesPreSportTotal))g"
                )
            )
        }

        lignes += evenements.map { evenement in
            LigneFrise(
                id: evenement.id,
                idEvenement: evenement.id,
                icone: evenement.icone,
                couleur: evenement.couleur,
                titre: evenement.titre,
                sousTitre: sousTitreEvenement(evenement),
                detail: evenement.detail
            )
        }

        return lignes
    }

    private func sousTitreEvenement(_ evenement: EvenementActivite) -> String {
        var parts = [Self.formatterHeure.string(from: evenement.date)]
        parts.append(descriptionPhase(tempsDe(evenement)))
        if evenement.pendantPause { parts.append("en pause") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Données dérivées

    private var seuils: SeuilsGlycemiques {
        ProfilService.shared.profil.seuilsGlycemiques
    }

    private var dureeEffortSec: TimeInterval {
        TimeInterval(activite.dureeMinutes * 60)
    }

    /// Fin en horloge murale relative au début (pauses réintégrées).
    private var finMurale: TimeInterval {
        activite.dateFin.timeIntervalSince(activite.dateDebut)
    }

    private var points: [GraphiqueGlycemique.PointCourbe] {
        reponse.pointsCgm.map {
            .init(temps: $0.secondesDepuisDebut, valeur: $0.valeur)
        }
    }

    private var domaineX: ClosedRange<TimeInterval> {
        (-30 * 60)...(finMurale + 30 * 60)
    }

    private var domaineY: ClosedRange<Double> {
        let valeurs = points.map(\.valeur)
        let bas = min(valeurs.min() ?? 70, 60) - 10
        let haut = max(valeurs.max() ?? 180, 200) + 10
        return bas...haut
    }

    private var yMarques: [Double] { [70, 100, 140, 180] }

    private var xMarques: [TimeInterval] {
        var marques: [TimeInterval] = [0]
        let pas: TimeInterval = finMurale > 60 * 60 ? 30 * 60 : 15 * 60
        var t = pas
        while t < finMurale {
            marques.append(t)
            t += pas
        }
        marques.append(finMurale)
        return marques
    }

    private var evenementsDansFenetre: [EvenementActivite] {
        evenements.filter {
            let t = tempsDe($0)
            return t >= domaineX.lowerBound && t <= domaineX.upperBound
        }
    }

    private var couleurCourbe: Color {
        if reponse.glycemieFin < seuils.hypoglycemie { return .red }
        if abs(reponse.deltaMgDl) < 20 { return .green }
        if reponse.deltaMgDl < -40 { return .orange }
        return .blue
    }

    private var couleurCurseur: Color { .primary }

    private var deltaFormate: String {
        let delta = Int(reponse.deltaMgDl.rounded())
        return delta > 0 ? "+\(delta)" : "\(delta)"
    }

    private func tempsDe(_ evenement: EvenementActivite) -> TimeInterval {
        evenement.date.timeIntervalSince(activite.dateDebut)
    }

    private func evenementLePlusProche(de temps: TimeInterval) -> EvenementActivite? {
        evenementsDansFenetre.min {
            abs(tempsDe($0) - temps) < abs(tempsDe($1) - temps)
        }
    }

    /// Glycémie interpolée linéairement à un instant donné.
    private func glycemie(a temps: TimeInterval) -> Double {
        let tries = points.sorted { $0.temps < $1.temps }
        guard let premier = tries.first, let dernier = tries.last else { return 0 }
        if temps <= premier.temps { return premier.valeur }
        if temps >= dernier.temps { return dernier.valeur }
        for i in 1..<tries.count where tries[i].temps >= temps {
            let a = tries[i - 1], b = tries[i]
            let plage = b.temps - a.temps
            guard plage > 0 else { return b.valeur }
            let ratio = (temps - a.temps) / plage
            return a.valeur + (b.valeur - a.valeur) * ratio
        }
        return dernier.valeur
    }

    private func couleurGlycemie(_ valeur: Double) -> Color {
        if valeur < seuils.hypoglycemie { return .red }
        if valeur > seuils.hyperglycemie { return .orange }
        return .primary
    }

    /// Situe un instant par rapport à l'effort — « avant », « 12 min
    /// d'effort », « après ».
    private func descriptionPhase(_ temps: TimeInterval) -> String {
        if temps < 0 {
            return "\(Int((-temps / 60).rounded())) min avant"
        }
        if temps > finMurale {
            return "\(Int(((temps - finMurale) / 60).rounded())) min après"
        }
        return "\(Int((temps / 60).rounded())) min d'effort"
    }

    private func labelTemps(_ temps: TimeInterval) -> String {
        if temps == 0 { return "T0" }
        let minutes = Int((temps / 60).rounded())
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes)min"
    }

    private func labelHorloge(_ temps: TimeInterval) -> String {
        Self.formatterHeure.string(from: activite.dateDebut.addingTimeInterval(temps))
    }

    private static let formatterHeure: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "H'h'mm"
        return f
    }()
}

// MARK: - LigneFrise

/// Ligne de la liste sous la courbe. `idEvenement` est `nil` pour les
/// entrées non positionnées dans le temps (glucides pré-sport) — elles ne
/// participent pas au couplage avec le curseur.
private struct LigneFrise: Identifiable {
    let id: String
    let idEvenement: String?
    let icone: String
    let couleur: Color
    let titre: String
    let sousTitre: String
    let detail: String
}
