//
//  SectionRatios.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Section « Ratios glucides / insuline » — choix du mode (unique ou par
/// moment), puis une ligne par ratio : valeur, date du dernier changement et
/// repas enregistrés depuis. Le réglage se fait dans une feuille, et un ratio
/// changé récemment est verrouillé (`CalculVerrouRatio`).
///
/// **Contrainte volontaire** : la bascule entre `.unique` et `.parMoment` ne
/// reporte aucune valeur, pour que l'utilisateur confirme explicitement les
/// nouveaux ratios. Elle les efface tous : elle est donc refusée tant qu'un
/// ratio est verrouillé, sinon elle contournerait le verrou.
struct SectionRatios: View {

    @Environment(ProfilService.self) private var service
    /// Optionnel : l'onboarding peut s'afficher avant le hub des repas.
    @Environment(RepasService.self) private var repasService: RepasService?

    @State private var ratioEdite: RatioRegle?
    @State private var alerteMode = false

    var body: some View {
        let lignes = self.lignes
        Section {
            Picker("Mode", selection: bindingMode(lignes)) {
                Text("Unique").tag(ModeRatio.unique)
                Text("Par moment").tag(ModeRatio.parMoment)
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .sheet(item: $ratioEdite) { ratio in
                feuille(ratio)
            }
            .alert("Un ratio est verrouillé", isPresented: $alerteMode) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Changer de mode efface tous les ratios. Ce sera possible quand aucun ne sera verrouillé.")
            }

            ForEach(lignes) { ligne in
                Button { ratioEdite = ligne.ratio } label: { vueLigne(ligne) }
                    .foregroundStyle(.primary)
            }
        } header: {
            Text("Ratios glucides / insuline")
        } footer: {
            Text("""
            Ces ratios sont utilisés comme référence d'analyse \
            uniquement. L'app ne calcule pas vos doses.
            """)
        }
    }

    // MARK: - Lignes

    private struct Ligne: Identifiable {
        let ratio: RatioRegle
        let valeur: Double?
        let dateChangement: Date?
        let nombreRepas: Int
        let etat: CalculVerrouRatio.Etat
        var id: RatioRegle { ratio }
        var estVerrouille: Bool { etat != .libre }
    }

    private var lignes: [Ligne] {
        let ratios: [RatioRegle] = service.profil.modeRatio == .unique
            ? [.unique]
            : [.petitDejeuner, .dejeuner, .gouter, .diner]
        return ratios.map(ligne)
    }

    private func ligne(_ ratio: RatioRegle) -> Ligne {
        let profil = service.profil
        let date = ratio.date(dans: profil.datesChangementRatioEffectives)
        let nombre = (repasService?.repas ?? []).filter { repas in
            (date.map { repas.heure >= $0 } ?? true)
                && ratio.couvre(repas.section(horaires: profil.horairesRepas))
        }.count
        return Ligne(
            ratio: ratio,
            valeur: ratio.valeur(dans: profil),
            dateChangement: date,
            nombreRepas: nombre,
            etat: CalculVerrouRatio.etat(dateChangement: date, repasDepuis: nombre, maintenant: Date())
        )
    }

    private func vueLigne(_ ligne: Ligne) -> some View {
        HStack(spacing: 10) {
            if ligne.estVerrouille {
                Image(systemName: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(ligne.ratio.libelle)
                Text(sousTitre(ligne))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(ligne.valeur.map(FormatRatio.valeur) ?? "Non défini")
                .fontWeight(ligne.valeur == nil ? .regular : .bold)
                .monospacedDigit()
                .fixedSize()
                .foregroundStyle(ligne.valeur == nil ? .secondary : .primary)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(ligne.estVerrouille ? "Verrouillé" : "")
    }

    private func sousTitre(_ ligne: Ligne) -> String {
        guard ligne.valeur != nil else { return "À renseigner" }
        guard let date = ligne.dateChangement else {
            return "Jamais modifié · \(ligne.nombreRepas) repas"
        }
        let depuis = Calendar.current.isDateInToday(date)
            ? "Depuis aujourd'hui"
            : "Depuis le \(FormatRatio.date(date))"
        return "\(depuis) · \(ligne.nombreRepas) repas"
    }

    private func feuille(_ ratio: RatioRegle) -> some View {
        let ligne = ligne(ratio)
        return FeuilleModificationRatio(
            libelle: ratio.libelle,
            valeurActuelle: ligne.valeur,
            dateChangement: ligne.dateChangement,
            nombreRepas: ligne.nombreRepas,
            etat: ligne.etat
        ) { nouveau in
            appliquer(nouveau, a: ratio)
        }
    }

    // MARK: - Écritures

    /// La date n'est posée que sur une vraie transition (valeur existante →
    /// différente) : la configuration initiale n'invalide aucun historique.
    private func appliquer(_ nouveau: Double, a ratio: RatioRegle) {
        service.mettreAJour { profil in
            let ancien = ratio.valeur(dans: profil)
            ratio.ecrire(nouveau, dans: profil)
            if let ancien, ancien != nouveau {
                var dates = profil.datesChangementRatioEffectives
                ratio.ecrireDate(Date(), dans: &dates)
                profil.datesChangementRatio = dates
                signalerChangement(libelle: ratio.libelle, nouveau: nouveau)
            }
        }
    }

    /// Confirme le changement **et son effet de bord** : l'analyse du ratio
    /// repart de zéro sur ce moment, les repas antérieurs n'étant plus
    /// comparables.
    private func signalerChangement(libelle: String, nouveau: Double) {
        guard nouveau > 0 else { return }
        ToastsService.shared.afficher(
            .reglage,
            titre: "\(libelle) : \(String(format: "1u/%.0fg", nouveau))",
            detail: "L'analyse de ce moment repart de zéro"
        )
    }

    private func bindingMode(_ lignes: [Ligne]) -> Binding<ModeRatio> {
        Binding(
            get: { service.profil.modeRatio },
            set: { nouveau in
                guard nouveau != service.profil.modeRatio else { return }
                guard !lignes.contains(where: \.estVerrouille) else {
                    alerteMode = true
                    return
                }
                service.mettreAJour { profil in
                    profil.modeRatio = nouveau
                    // Pas de transfert entre modes : on remet à zéro pour
                    // forcer la saisie explicite. Les dates de l'ancien mode
                    // décrivaient des ratios qui viennent d'être effacés.
                    profil.ratioUnique = nil
                    profil.ratiosParMoment = RatiosParMoment()
                    profil.datesChangementRatio = DatesChangementRatio()
                }
            }
        )
    }
}

// MARK: - Ratio réglé

/// Un ratio de la page, et où lire ou écrire sa valeur et sa date.
private enum RatioRegle: String, Identifiable {
    case unique, petitDejeuner, dejeuner, gouter, diner

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .unique:        "Ratio"
        case .petitDejeuner: "Petit-déjeuner"
        case .dejeuner:      "Déjeuner"
        case .gouter:        "Goûter"
        case .diner:         "Dîner"
        }
    }

    /// Même correspondance que `AnalyseRatioService.dateChangement` : la nuit
    /// relève du ratio du dîner.
    func couvre(_ section: SectionRepas) -> Bool {
        switch self {
        case .unique:        true
        case .petitDejeuner: section == .petitDejeuner
        case .dejeuner:      section == .dejeuner
        case .gouter:        section == .enCas
        case .diner:         section == .diner || section == .nuit
        }
    }

    private var cheminValeur: WritableKeyPath<RatiosParMoment, Double?>? {
        switch self {
        case .unique:        nil
        case .petitDejeuner: \.petitDejeuner
        case .dejeuner:      \.dejeuner
        case .gouter:        \.gouter
        case .diner:         \.diner
        }
    }

    private var cheminDate: WritableKeyPath<DatesChangementRatio, Date?> {
        switch self {
        case .unique:        \.unique
        case .petitDejeuner: \.petitDejeuner
        case .dejeuner:      \.dejeuner
        case .gouter:        \.gouter
        case .diner:         \.diner
        }
    }

    func valeur(dans profil: ProfilUtilisateur) -> Double? {
        guard let cheminValeur else { return profil.ratioUnique }
        return profil.ratiosParMoment[keyPath: cheminValeur]
    }

    func ecrire(_ valeur: Double, dans profil: ProfilUtilisateur) {
        guard let cheminValeur else {
            profil.ratioUnique = valeur
            return
        }
        profil.ratiosParMoment[keyPath: cheminValeur] = valeur
    }

    func date(dans dates: DatesChangementRatio) -> Date? {
        dates[keyPath: cheminDate]
    }

    func ecrireDate(_ date: Date, dans dates: inout DatesChangementRatio) {
        dates[keyPath: cheminDate] = date
    }
}
