//
//  VuesEpisodesCharge.swift
//  diaviz
//
//  Écrans des épisodes de charge (C1 § 9) : carte de l'épisode en cours,
//  réglages actuels, fois précédentes, détail d'un épisode passé et d'un
//  réglage. Règles d'interface : CLAUDE.md § « Concevoir l'interface ».
//

import SwiftUI

// MARK: - Mise en forme

enum FormatEpisode {

    private static let fr = Locale(identifier: "fr_FR")

    static func nombre(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...1)).locale(fr))
    }

    static func unite(_ r: ReglageSuivi) -> String {
        if case .lente = r { return "U" }
        return "g/U"
    }

    static func valeur(_ v: Double?, _ r: ReglageSuivi) -> String {
        guard let v else { return "—" }
        return "\(nombre(v)) \(unite(r))"
    }

    static func titre(_ r: ReglageSuivi) -> String {
        switch r {
        case .lente:              "Lente"
        case .ratio(let m):       m.libelle
        case .ratioSport(let t):  t
        }
    }

    static func estNuit(_ r: ReglageSuivi) -> Bool {
        if case .lente = r { return true }
        return false
    }

    static func evenements(_ r: ReglageSuivi, _ n: Int) -> String {
        estNuit(r) ? (n > 1 ? "nuits" : "nuit") : "repas"
    }

    static func concluants(_ r: ReglageSuivi, _ n: Int) -> String {
        estNuit(r) ? (n > 1 ? "concluantes" : "concluante") : (n > 1 ? "concluants" : "concluant")
    }

    static func niveau(_ n: NiveauChargeActive?) -> String {
        switch n {
        case .haute:   "Charge haute"
        case .normale: "Dans la référence"
        case .basse:   "Charge basse"
        case nil:      "Sans référence"
        }
    }

    /// Le niveau dit avec les mots de l'utilisateur (carte « En ce moment »).
    static func phrase(_ n: NiveauChargeActive?) -> String {
        switch n {
        case .haute:   "Plus d'activité que d'habitude"
        case .normale: "Activité habituelle"
        case .basse:   "Moins d'activité que d'habitude"
        case nil:      "Référence en cours de calcul"
        }
    }

    static func symbole(_ n: NiveauChargeActive?) -> String {
        switch n {
        case .haute:   "arrow.up"
        case .normale: "equal"
        case .basse:   "arrow.down"
        case nil:      "hourglass"
        }
    }

    static func couleur(_ n: NiveauChargeActive?) -> Color {
        switch n {
        case .haute:   .blue
        case .basse:   .red
        case .normale: .primary
        case nil:      .secondary
        }
    }

    static func date(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated).locale(fr))
    }

    static func mois(_ d: Date) -> String {
        d.formatted(.dateTime.month(.abbreviated).locale(fr))
    }

    static func duree(jours: Int) -> String {
        if jours < 14 { return "\(jours) jour\(jours > 1 ? "s" : "")" }
        return "\(Int((Double(jours) / 7).rounded())) sem."
    }

    static func periode(_ e: EpisodeCharge) -> String {
        "\(date(e.debut)) → \(date(e.dernierJour))"
    }

    static func moisPeriode(_ e: EpisodeCharge) -> String {
        let a = mois(e.debut), b = mois(e.dernierJour)
        return a == b ? a : "\(a) – \(b)"
    }

    static func faitsCourts(_ f: FaitsEpisode) -> String {
        "\(nombre(f.seancesParSemaine)) séance\(f.seancesParSemaine >= 2 ? "s" : "") · \(DureeActivite.texte(f.minutesMarcheParSemaine)) de marche / sem."
    }

    static func icone(_ etat: EtatReglage) -> (nom: String, couleur: Color) {
        switch etat {
        case .concluant:       ("checkmark.circle.fill", .green)
        case .ajustement:      ("arrow.triangle.2.circlepath.circle.fill", .orange)
        case .observation:     ("clock.circle.fill", .cyan)
        case .pasAssezDeRecul: ("hourglass.circle.fill", .gray)
        }
    }

    static func libelle(_ etat: EtatReglage, _ r: ReglageSuivi) -> String {
        switch etat {
        case .concluant:       estNuit(r) ? "Concluante" : "Concluant"
        case .ajustement:      "En ajustement"
        case .observation:     "En observation"
        case .pasAssezDeRecul: "Pas assez de recul"
        }
    }

    /// Ligne de compte d'un réglage actuel (écran 1).
    static func compte(_ e: EtatReglageActuel) -> String {
        let r = e.reglage
        switch e.etat {
        case let .pasAssezDeRecul(n, requis):
            return "\(n) \(evenements(r, max(n, requis))) sur \(requis) nécessaires"
        case let .observation(faites, sur):
            return faites == 0 ? "Nouvelle dose · \(sur) nuits d'observation" : "Nouvelle dose · nuit \(faites) sur \(sur)"
        case let .ajustement(c, n, h), let .concluant(c, n, h):
            var texte = e.changement == nil
                ? "\(c) \(evenements(r, c)) \(concluants(r, c)) sur \(n)"
                : "\(c) sur \(n)"
            if h >= RegleEtatReglage.hyposBloquantes { texte += " · \(h) hypos" }
            if let changement = e.changement { texte += " · changé le \(date(changement.date))" }
            return texte
        }
    }
}

// MARK: - Briques

struct TitreSectionEpisode: View {
    let texte: String
    /// Pastille à droite du titre (« Nouvel épisode »).
    var badge: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(texte)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let badge {
                Text(badge)
                    .font(.caption.bold())
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.15), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .padding(.horizontal, 4)
    }
}

struct SousTitreSectionEpisode: View {
    let texte: String
    var body: some View {
        Text(texte)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Ligne de liste groupée : icône, titre, une ligne de valeur et une ligne
/// secondaire au plus, valeur et légende en petit à droite.
struct LigneEpisode: View {
    var icone: (nom: String, couleur: Color)? = nil
    let titre: String
    var ligneValeur: String? = nil
    var sousTitre: String? = nil
    var valeur: String? = nil
    var legende: String? = nil
    var chevron = false

    var body: some View {
        HStack(spacing: 12) {
            if let icone {
                Image(systemName: icone.nom)
                    .font(.title3)
                    .foregroundStyle(icone.couleur)
                    .frame(width: 26)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(titre)
                if let ligneValeur {
                    Text(ligneValeur)
                        .font(.subheadline)
                        .monospacedDigit()
                }
                if let sousTitre {
                    Text(sousTitre)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if valeur != nil || legende != nil {
                VStack(alignment: .trailing, spacing: 1) {
                    if let valeur {
                        Text(valeur).monospacedDigit()
                    }
                    if let legende {
                        Text(legende)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Liste groupée façon iOS : lignes séparées par un filet, dans une carte.
struct ListeEpisode<Contenu: View>: View {
    @ViewBuilder let contenu: Contenu
    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: contenu) { lignes in
                ForEach(Array(lignes.enumerated()), id: \.offset) { index, ligne in
                    if index > 0 { Divider().padding(.leading, 16) }
                    ligne
                }
            }
        }
        .surfaceCarte()
    }
}

// MARK: - Écran 1 : en ce moment

struct CarteEpisodeEnCours: View {
    let episode: EpisodeCharge?
    let precedent: EpisodeCharge?
    let charge: SyntheseChargeActive?

    /// Épisode ouvert depuis moins de `joursNouvelEpisode` jours, après un
    /// autre — badge « Nouvel épisode » à côté du titre de section.
    static func estNouveau(_ episode: EpisodeCharge?, precedent: EpisodeCharge?) -> Bool {
        guard let episode, precedent != nil else { return false }
        return episode.faits.jours <= CalculEpisodesCharge.joursNouvelEpisode
    }

    private var estNouveau: Bool { Self.estNouveau(episode, precedent: precedent) }

    private var ecart: String {
        guard case let .disponible(indice, _, _) = charge?.etat else { return "—" }
        let pct = Int(((indice - 1) * 100).rounded())
        return pct == 0 ? "0 %" : "\(pct > 0 ? "+" : "\u{2212}")\(abs(pct)) %"
    }

    var body: some View {
        Group {
            if let episode {
                contenu(episode)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Lecture d'Apple Santé…").foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCarte()
    }

    private func contenu(_ episode: EpisodeCharge) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: FormatEpisode.symbole(episode.niveau))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(teinte(episode.niveau))
                    .frame(width: 40, height: 40)
                    .background(teinte(episode.niveau).opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(FormatEpisode.phrase(episode.niveau))
                        .font(.headline)
                    // Une ligne si elle tient ; sinon niveau et date sur deux
                    // lignes entières, jamais un bout de date seul en dessous.
                    ViewThatFits(in: .horizontal) {
                        Text("\(FormatEpisode.niveau(episode.niveau)) · \(depuis(episode))")
                            .lineLimit(1)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(FormatEpisode.niveau(episode.niveau))
                            Text("D" + depuis(episode).dropFirst())
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack(alignment: .top, spacing: 0) {
                chiffre(ecart, "vs référence")
                Divider().padding(.horizontal, 10)
                chiffre(FormatEpisode.nombre(episode.faits.seancesParSemaine), "séances / sem.")
                Divider().padding(.horizontal, 10)
                chiffre(DureeActivite.texte(episode.faits.minutesMarcheParSemaine), "marche / sem.")
            }
            .fixedSize(horizontal: false, vertical: true)
            if estNouveau, let precedent {
                Divider()
                Text("Avant : \(FormatEpisode.niveau(precedent.niveau).lowercased()), \(FormatEpisode.duree(jours: precedent.faits.jours))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if charge?.marcheIncluse == false {
                Text("Séances seules : pas non lus depuis Apple Santé.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func chiffre(_ valeur: String, _ legende: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(valeur).font(.title3.weight(.semibold)).monospacedDigit()
            Text(legende).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func depuis(_ episode: EpisodeCharge) -> String {
        "depuis le \(FormatEpisode.date(episode.debut)) · \(FormatEpisode.duree(jours: episode.faits.jours))"
    }

    /// Couleur de l'icône : celle du niveau, gris pour la référence et
    /// l'absence de référence (le neutre `.primary` ne se teinte pas).
    private func teinte(_ n: NiveauChargeActive?) -> Color {
        switch n {
        case .haute, .basse: FormatEpisode.couleur(n)
        case .normale, nil:  .gray
        }
    }
}

// MARK: - Écran 1 : vos réglages

struct SectionReglagesActuels: View {
    let synthese: SyntheseEpisodesCharge

    private var lente: [EtatReglageActuel] { synthese.etatsActuels.filter { if case .lente = $0.reglage { return true }; return false } }
    private var repas: [EtatReglageActuel] { synthese.etatsActuels.filter { if case .ratio = $0.reglage { return true }; return false } }
    private var sport: [EtatReglageActuel] { synthese.etatsActuels.filter { if case .ratioSport = $0.reglage { return true }; return false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            groupe("Lente", lente)
            groupe("Repas", repas)
            groupe("Activité physique", sport)
        }
    }

    @ViewBuilder
    private func groupe(_ titre: String, _ etats: [EtatReglageActuel]) -> some View {
        if !etats.isEmpty {
            SousTitreSectionEpisode(texte: titre)
            ListeEpisode {
                ForEach(etats) { etat in
                    NavigationLink {
                        PageReglageEpisodes(etat: etat, synthese: synthese)
                    } label: {
                        LigneEpisode(
                            icone: FormatEpisode.icone(etat.etat),
                            titre: FormatEpisode.titre(etat.reglage),
                            sousTitre: FormatEpisode.compte(etat),
                            valeur: FormatEpisode.valeur(etat.valeur, etat.reglage),
                            legende: "actuel",
                            chevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Écran 1 : les fois précédentes

struct SectionFoisPrecedentes: View {
    let synthese: SyntheseEpisodesCharge

    var body: some View {
        ListeEpisode {
            if synthese.comparables.isEmpty {
                Text("Aucun épisode comparable pour l'instant.")
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(synthese.comparables) { episode in
                NavigationLink {
                    PageEpisodeCharge(episode: episode, synthese: synthese)
                } label: {
                    LigneEpisode(
                        titre: FormatEpisode.periode(episode),
                        sousTitre: FormatEpisode.faitsCourts(episode.faits),
                        chevron: true
                    )
                }
                .buttonStyle(.plain)
            }
            NavigationLink {
                PageAutresEpisodes(synthese: synthese)
            } label: {
                LigneEpisode(titre: "Autres épisodes", valeur: "\(synthese.autres.count)", chevron: true)
            }
            .buttonStyle(.plain)
            .disabled(synthese.autres.isEmpty)
        }
    }
}

struct PageAutresEpisodes: View {
    let synthese: SyntheseEpisodesCharge

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SousTitreSectionEpisode(texte: "Charge réelle différente de l'épisode en cours.")
                ListeEpisode {
                    ForEach(synthese.autres) { episode in
                        NavigationLink {
                            PageEpisodeCharge(episode: episode, synthese: synthese)
                        } label: {
                            LigneEpisode(
                                titre: FormatEpisode.periode(episode),
                                sousTitre: "\(FormatEpisode.niveau(episode.niveau)) · \(FormatEpisode.faitsCourts(episode.faits))",
                                chevron: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Autres épisodes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Écran 2 : un épisode passé

struct PageEpisodeCharge: View {
    let episode: EpisodeCharge
    let synthese: SyntheseEpisodesCharge

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                TitreSectionEpisode(texte: "L'épisode")
                entete
                TitreSectionEpisode(texte: "Vos réglages à l'époque")
                SousTitreSectionEpisode(texte: "Valeur la plus concluante de l'épisode.")
                groupe("Lente") { if case .lente = $0 { return true }; return false }
                groupe("Repas") { if case .ratio = $0 { return true }; return false }
                groupe("Activité physique") { if case .ratioSport = $0 { return true }; return false }
                if episode.reglages.isEmpty {
                    Text("Aucune nuit ni aucun repas jugés pendant cet épisode.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }
                TitreSectionEpisode(texte: "Résultats")
                resultats
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(FormatEpisode.periode(episode))
        .navigationBarTitleDisplayMode(.inline)
        .boutonCriteresEpisodes()
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(FormatEpisode.niveau(episode.niveau))
                    .font(.title2.bold())
                    .foregroundStyle(FormatEpisode.couleur(episode.niveau))
                Text(FormatEpisode.moisPeriode(episode)).foregroundStyle(.secondary)
            }
            Divider()
            HStack(alignment: .top, spacing: 0) {
                chiffre(FormatEpisode.duree(jours: episode.faits.jours), "durée")
                Divider().padding(.horizontal, 10)
                chiffre(FormatEpisode.nombre(episode.faits.seancesParSemaine), "séances / sem.")
                Divider().padding(.horizontal, 10)
                chiffre(DureeActivite.texte(episode.faits.minutesMarcheParSemaine), "marche / sem.")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCarte()
    }

    private func chiffre(_ valeur: String, _ legende: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(valeur).font(.title3.weight(.semibold)).monospacedDigit()
            Text(legende).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func groupe(_ titre: String, _ filtre: (ReglageSuivi) -> Bool) -> some View {
        let reglages = episode.reglages.filter { filtre($0.reglage) }
        if !reglages.isEmpty {
            SousTitreSectionEpisode(texte: titre)
            ListeEpisode {
                ForEach(reglages, id: \.reglage) { ligne($0) }
            }
        }
    }

    private func ligne(_ r: ReglageEpisode) -> LigneEpisode {
        let actuel = synthese.etatsActuels.first { $0.reglage == r.reglage }?.valeur
        let aujourdhui = "Auj. \(FormatEpisode.valeur(actuel, r.reglage))"
        let titre = FormatEpisode.titre(r.reglage)
        switch r.retenue {
        case .concluante(let u) where u.valeur != nil:
            return LigneEpisode(
                icone: ("checkmark.circle.fill", .green), titre: titre,
                ligneValeur: "\(FormatEpisode.valeur(u.valeur, r.reglage)) · \(u.concluants) \(FormatEpisode.evenements(r.reglage, u.evaluables)) sur \(u.evaluables)",
                legende: aujourdhui
            )
        case .concluante:
            return LigneEpisode(icone: ("circle.dashed", .secondary), titre: titre, ligneValeur: "Valeur non enregistrée", legende: aujourdhui)
        case .aucune(let derniere):
            return LigneEpisode(
                icone: ("circle.dashed", .secondary), titre: titre, ligneValeur: "Aucune valeur concluante",
                legende: "Dernière \(FormatEpisode.valeur(derniere, r.reglage))\n\(aujourdhui)"
            )
        case .pasAssezDeRecul:
            return LigneEpisode(icone: ("circle.dashed", .secondary), titre: titre, ligneValeur: "Pas assez de recul", legende: aujourdhui)
        }
    }

    private var resultats: some View {
        let r = episode.resultats
        func pct(_ v: Double?) -> String { v.map { "\(Int($0.rounded())) %" } ?? "Pas assez de recul" }
        return ListeEpisode {
            LigneEpisode(titre: "Temps dans la cible", valeur: pct(r.tempsDansLaCible))
            LigneEpisode(titre: "Score moyen", valeur: r.scoreMoyen.map { "\(Int($0.rounded())) /100" } ?? "Pas assez de recul")
            LigneEpisode(titre: "Resucrages", valeur: r.resucragesParJour.map { "\(FormatEpisode.nombre($0)) / jour" } ?? "Pas assez de recul")
            LigneEpisode(titre: "Couverture CGM", valeur: pct(r.couvertureCGM))
        }
    }
}

// MARK: - Écran 3 : un réglage

struct PageReglageEpisodes: View {
    let etat: EtatReglageActuel
    let synthese: SyntheseEpisodesCharge

    private var reglage: ReglageSuivi { etat.reglage }
    private var estLente: Bool { FormatEpisode.estNuit(reglage) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                TitreSectionEpisode(texte: estLente ? "Dose actuelle" : "Valeur actuelle")
                valeurActuelle
                TitreSectionEpisode(texte: estLente ? "Nuits de l'épisode" : "Repas de l'épisode")
                pastilles
                TitreSectionEpisode(texte: estLente ? "Doses déjà utilisées" : "Valeurs déjà utilisées")
                dejaUtilisees
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(FormatEpisode.titre(reglage))
        .navigationBarTitleDisplayMode(.inline)
        .boutonCriteresEpisodes()
    }

    private var valeurActuelle: some View {
        let icone = FormatEpisode.icone(etat.etat)
        let pourquoi: String? = {
            if let changement = etat.changement {
                return "\(estLente ? "Nouvelle dose" : "Changé") le \(FormatEpisode.date(changement.date))"
            }
            return etat.depuis.map { "Depuis le \(FormatEpisode.date($0))" }
        }()
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(etat.valeur.map(FormatEpisode.nombre) ?? "—")
                    .font(.system(size: 40, weight: .bold))
                    .monospacedDigit()
                Text(FormatEpisode.unite(reglage)).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            }
            Label(FormatEpisode.libelle(etat.etat, reglage), systemImage: icone.nom)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(icone.couleur)
            if let pourquoi {
                Text(pourquoi).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private var pastilles: some View {
        let regle = reglage.regle
        let recents = Array(etat.evenements.suffix(regle.fenetre))
        let aVenir = max(0, regle.fenetre - recents.count)
        return VStack(alignment: .leading, spacing: 10) {
            if recents.isEmpty {
                Text(estLente ? "Aucune nuit dans cet épisode pour l'instant." : "Aucun repas dans cet épisode pour l'instant.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                ForEach(recents) { e in
                    VStack(spacing: 4) {
                        pastille(e)
                        Text(e.date.formatted(.dateTime.day())).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                ForEach(0..<aVenir, id: \.self) { _ in
                    VStack(spacing: 4) {
                        Circle().strokeBorder(Color(.tertiaryLabel), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                            .frame(width: 22, height: 22)
                        Text(" ").font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                }
            }
            legende(recents)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCarte()
    }

    @ViewBuilder
    private func pastille(_ e: EvenementAffiche) -> some View {
        if e.enObservation {
            Circle().strokeBorder(Color.cyan, style: StrokeStyle(lineWidth: 2, dash: [3, 2])).frame(width: 22, height: 22)
                .accessibilityLabel("Observation")
        } else {
            switch e.issue {
            case .concluant:    Circle().fill(Color.green).frame(width: 22, height: 22).accessibilityLabel("Concluant")
            case .rate:         Circle().fill(Color.orange).frame(width: 22, height: 22).accessibilityLabel(estLente ? "Dérive" : "Hors cible")
            case .hypo:         Circle().fill(Color.red).frame(width: 22, height: 22).accessibilityLabel("Hypo")
            case .nonEvaluable: Circle().strokeBorder(Color(.secondaryLabel), lineWidth: 1.5).frame(width: 22, height: 22).accessibilityLabel("Non évaluable")
            }
        }
    }

    private func legende(_ evenements: [EvenementAffiche]) -> some View {
        let issues = Set(evenements.filter { !$0.enObservation }.map(\.issue))
        let observation = evenements.contains(where: \.enObservation)
        return HStack(spacing: 12) {
            if issues.contains(.concluant) { cle(Color.green, estLente ? "Concluante" : "Concluant") }
            if issues.contains(.rate) { cle(Color.orange, estLente ? "Dérive" : "Hors cible") }
            if issues.contains(.hypo) { cle(Color.red, "Hypo") }
            if issues.contains(.nonEvaluable) { cle(nil, "Non évaluable") }
            if observation { cle(Color.cyan, "Observation") }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func cle(_ couleur: Color?, _ texte: String) -> some View {
        HStack(spacing: 4) {
            if let couleur {
                Circle().fill(couleur).frame(width: 8, height: 8)
            } else {
                Circle().strokeBorder(Color(.secondaryLabel), lineWidth: 1).frame(width: 8, height: 8)
            }
            Text(texte)
        }
    }

    /// Une ligne par valeur et par épisode, plus récent d'abord ; la valeur
    /// en cours dans l'épisode en cours est déjà en tête de page.
    private var usages: [(episode: EpisodeCharge, usage: UsageValeur)] {
        var lignes: [(EpisodeCharge, UsageValeur)] = []
        let episodes = ([synthese.enCours].compactMap { $0 } + synthese.episodesPasses)
        for episode in episodes {
            let reglages = episode.reglages.first { $0.reglage == reglage }?.usages ?? []
            for (index, u) in reglages.enumerated().reversed() {
                let estCourante = episode.enCours && index == reglages.count - 1 && u.valeur == etat.valeur
                if !estCourante { lignes.append((episode, u)) }
            }
        }
        return lignes
    }

    @ViewBuilder
    private var dejaUtilisees: some View {
        let lignes = usages
        if lignes.isEmpty {
            Text("Aucune autre valeur pour l'instant.")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        } else {
            ListeEpisode {
                ForEach(Array(lignes.enumerated()), id: \.offset) { _, ligne in
                    NavigationLink {
                        PageEpisodeCharge(episode: ligne.episode, synthese: synthese)
                    } label: {
                        LigneEpisode(
                            icone: ligne.usage.aEteConcluante ? ("checkmark.circle.fill", .green) : ("circle.dashed", .secondary),
                            titre: FormatEpisode.valeur(ligne.usage.valeur, reglage),
                            sousTitre: "\(FormatEpisode.niveau(ligne.episode.niveau)) · \(FormatEpisode.moisPeriode(ligne.episode))",
                            valeur: ligne.usage.tropCourt ? "—" : "\(ligne.usage.concluants)/\(ligne.usage.evaluables)",
                            legende: ligne.usage.tropCourt ? "trop court" : FormatEpisode.evenements(reglage, ligne.usage.evaluables),
                            chevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Critères (feuille « i »)

/// Seuils et critères des épisodes, lus dans les constantes du calcul
/// (source unique, C1 § 6-8). Ouverte par le bouton « i » des écrans.
struct FeuilleCriteresEpisodes: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    TitreSectionEpisode(texte: "Épisode")
                    ListeEpisode {
                        LigneEpisode(titre: "Même niveau de charge", sousTitre: "Un changement de réglage ne coupe jamais un épisode.")
                        LigneEpisode(titre: "Comparable", sousTitre: "Charge moyenne à ±\(Int(CalculEpisodesCharge.ecartChargeComparable * 100)) % de l'épisode en cours.")
                        LigneEpisode(titre: "Historique", sousTitre: "\(CalculChargeActive.horizonJours / 30) derniers mois.")
                    }

                    TitreSectionEpisode(texte: "Concluant, c'est")
                    ListeEpisode {
                        LigneEpisode(titre: "Une nuit", sousTitre: "Nuit profonde stable, aucune hypo.")
                        LigneEpisode(titre: "Un repas", sousTitre: "Aucune hypo, pic sous 180 ou vite revenu.")
                        LigneEpisode(titre: "Non compté", sousTitre: "Repas revenu lentement en cible, nuit ou repas non analysable.")
                    }

                    TitreSectionEpisode(texte: "Seuils")
                    ListeEpisode {
                        seuil("Lente", .lente, "dernières nuits")
                        seuil("Ratio de repas", .ratioRepas, "derniers repas")
                        seuil("Ratio sport, par type", .ratioSport, "derniers repas")
                    }

                    TitreSectionEpisode(texte: "Toujours")
                    ListeEpisode {
                        LigneEpisode(titre: "\(RegleEtatReglage.hyposBloquantes) hypos", sousTitre: "Jamais concluant, quel que soit le compte.")
                        LigneEpisode(titre: "Nouvelle dose de lente", sousTitre: "\(RegleEtatReglage.lente.transition) nuits en observation, non comptées.")
                        LigneEpisode(titre: "Nouvel épisode", sousTitre: "Les compteurs repartent de zéro.")
                    }

                    TitreSectionEpisode(texte: "Résultats d'un épisode")
                    ListeEpisode {
                        LigneEpisode(titre: "Temps dans la cible, score", valeur: "dès \(CalculEpisodesCharge.joursMinimumNiveauGlycemie) jours")
                        LigneEpisode(titre: "Resucrages par jour", valeur: "dès \(CalculEpisodesCharge.joursMinimumResucrages) jours")
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Critères")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    private func seuil(_ titre: String, _ regle: RegleEtatReglage, _ unite: String) -> LigneEpisode {
        LigneEpisode(
            titre: titre,
            ligneValeur: "Concluant à \(regle.entree) sur les \(regle.fenetre) \(unite)",
            sousTitre: "Minimum \(regle.minimum) · repasse en ajustement à \(regle.sortie) ou moins"
        )
    }
}

/// Bouton « i » de barre de navigation qui ouvre `FeuilleCriteresEpisodes`.
struct BoutonCriteresEpisodes: ViewModifier {
    @State private var ouverte = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Critères", systemImage: "info.circle") { ouverte = true }
                }
            }
            .sheet(isPresented: $ouverte) {
                FeuilleCriteresEpisodes()
            }
    }
}

extension View {
    func boutonCriteresEpisodes() -> some View { modifier(BoutonCriteresEpisodes()) }
}
