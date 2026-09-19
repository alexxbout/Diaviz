//
//  EmpreinteGlycemiqueWidget.swift
//  DiavizSportWidget
//
//  Widget écran d'accueil (.systemSmall / .systemMedium / .systemLarge
//  uniquement — pas de Lock Screen, qui imposerait un rendu monochrome
//  incompatible avec la couleur dérivée du GRI). Affiche l'empreinte
//  glycémique du jour en cours, lue depuis l'instantané que `ScoreService`
//  publie en App Group (`EmpreinteWidgetSnapshot`). Rétrospectif par
//  conception, comme le reste du CGM dans l'app : pas de lecture directe de
//  HealthKit/SwiftData ici, budget de rafraîchissement décidé par iOS
//  (`TimelineProvider`).
//
//  Deux modes, choisis dans l'éditeur de widget (appui long → Modifier le
//  widget) : "Empreinte seule" (fond transparent, cercle centré, aucune
//  autre info) ou complet (cercle + score, fond opaque). `.systemSmall`
//  étant carré, il force toujours le mode empreinte seule.
//

import WidgetKit
import SwiftUI
import AppIntents

struct EmpreinteConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Empreinte glycémique"
    static var description = IntentDescription("Choisir l'affichage du widget empreinte glycémique.")

    @Parameter(title: "Empreinte seule", description: "N'affiche que le cercle, fond transparent.", default: false)
    var empreinteSeule: Bool
}

struct EmpreinteEntry: TimelineEntry {
    let date: Date
    /// `nil` = pas d'instantané, ou instantané trop ancien pour être fiable
    /// (app pas relancée depuis longtemps) → rendu neutre, jamais une
    /// empreinte périmée présentée comme celle d'aujourd'hui.
    let instantane: EmpreinteWidgetSnapshot?
    let empreinteSeule: Bool

    /// Un instantané est jugé exploitable moins de 12h après son écriture —
    /// au-delà, il appartient quasi certainement à une autre journée
    /// métabolique. Marge large : pas de garantie d'exécution en fond côté
    /// app (cf. HealthKit background delivery, best-effort).
    private static let ageMax: TimeInterval = 12 * 3600

    static func depuisSnapshotBrut(
        _ brut: EmpreinteWidgetSnapshot?,
        empreinteSeule: Bool,
        maintenant: Date = Date()
    ) -> EmpreinteEntry {
        let valide = brut.flatMap { instantane -> EmpreinteWidgetSnapshot? in
            maintenant.timeIntervalSince(instantane.ecritLe) < ageMax ? instantane : nil
        }
        return EmpreinteEntry(date: maintenant, instantane: valide, empreinteSeule: empreinteSeule)
    }
}

struct EmpreinteGlycemiqueProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> EmpreinteEntry {
        EmpreinteEntry(date: Date(), instantane: nil, empreinteSeule: false)
    }

    func snapshot(for configuration: EmpreinteConfigurationIntent, in context: Context) async -> EmpreinteEntry {
        .depuisSnapshotBrut(EmpreinteWidgetSnapshot.lire(), empreinteSeule: configuration.empreinteSeule)
    }

    func timeline(for configuration: EmpreinteConfigurationIntent, in context: Context) async -> Timeline<EmpreinteEntry> {
        let entree = EmpreinteEntry.depuisSnapshotBrut(EmpreinteWidgetSnapshot.lire(), empreinteSeule: configuration.empreinteSeule)
        // Rafraîchissement dans 1h : l'app republie l'instantané et recharge
        // le widget elle-même (`WidgetCenter.reloadTimelines`) à chaque
        // nouvelle donnée ; cette entrée périodique couvre le cas où l'app
        // ne tourne pas.
        let prochain = Calendar.current.date(byAdding: .hour, value: 1, to: entree.date) ?? entree.date.addingTimeInterval(3600)
        return Timeline(entries: [entree], policy: .after(prochain))
    }
}

struct EmpreinteGlycemiqueWidgetVue: View {
    let entree: EmpreinteEntry
    @Environment(\.widgetFamily) private var famille
    @Environment(\.widgetRenderingMode) private var modeRendu

    /// `.systemSmall` est carré : toujours cercle seul, quel que soit le
    /// réglage — un score en texte n'y tient de toute façon pas lisiblement.
    private var cercleSeul: Bool { famille == .systemSmall || entree.empreinteSeule }

    /// En mode teinté/monochrome (réglage écran d'accueil "Teinté"/"Clair
    /// verre"), le disque de fond blanc masquerait le fond système —
    /// seuls les anneaux (marqués `.widgetAccentable`) restent visibles,
    /// dans la teinte unique choisie par iOS. En mode couleur normale, le
    /// disque reste (lisibilité sur fond d'écran opaque imposé par iOS).
    private var plaqueVisible: Bool { modeRendu == .fullColor }

    var body: some View {
        Group {
            if cercleSeul {
                GeometryReader { geo in
                    let diametre = min(geo.size.width, geo.size.height) * 1.02
                    empreinte(diametre: diametre)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            } else {
                HStack(spacing: 16) {
                    empreinte(diametre: famille == .systemLarge ? 190 : 128)
                    if let instantane = entree.instantane {
                        details(instantane)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .containerBackground(for: .widget) {
            if cercleSeul {
                Color.clear
            } else {
                Color(.tertiarySystemFill)
            }
        }
    }

    /// `anime: true` rejoue le tracé du centre vers le bord à chaque
    /// nouvelle entrée de timeline — seule animation possible côté widget
    /// (pas de process persistant : la dérive continue "vivante" de la vue
    /// détail dans l'app ne peut pas tourner ici, WidgetKit ne rend qu'un
    /// instantané statique par entrée).
    @ViewBuilder
    private func empreinte(diametre: CGFloat) -> some View {
        if let instantane = entree.instantane {
            EmpreinteGlycemiqueVue(anneaux: instantane.anneaux, score: instantane.score, diametre: diametre, anime: true, plaqueVisible: plaqueVisible)
        } else {
            // Pas d'instantané exploitable : anneaux neutres en pointillés
            // (même convention que `EmpreinteGlycemiqueVue` pour un jour
            // sans CGM), jamais un cadran vide.
            EmpreinteGlycemiqueVue(anneaux: [], score: nil, diametre: diametre, plaqueVisible: plaqueVisible)
        }
    }

    @ViewBuilder
    private func details(_ instantane: EmpreinteWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Empreinte du jour")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(instantane.score.map { "\($0)" } ?? "—")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("/ 100")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct EmpreinteGlycemiqueWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: EmpreinteWidgetKind.identifiant,
            intent: EmpreinteConfigurationIntent.self,
            provider: EmpreinteGlycemiqueProvider()
        ) { entree in
            EmpreinteGlycemiqueWidgetVue(entree: entree)
        }
        .configurationDisplayName("Empreinte glycémique")
        .description("Empreinte glycémique du jour en cours.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
