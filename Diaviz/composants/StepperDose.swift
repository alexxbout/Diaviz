//
//  StepperDose.swift
//  diaviz
//

import SwiftUI

/// Stepper de dose horizontal — `−` / valeur centrale **tappable** / `+`.
///
/// Le tap sur la valeur ouvre une alerte de saisie directe au clavier : sur
/// une dose de 12u, atteindre la valeur au pas de 0,5 demandait 24 taps.
/// Partagé par toutes les saisies de dose de l'app (dose d'un aliment, dose
/// globale du repas, correction d'hyperglycémie, valeur d'un ajustement) pour
/// que le geste soit le même partout — c'est `BoutonStepper` qui reste le
/// bouton unitaire, ce composant assemble la ligne complète.
///
/// Deux modes de valeur :
/// - `Binding<Double>` : la valeur existe toujours (correction, ajustement).
/// - `Binding<Double?>` : `nil` = non renseigné, affiché « — » (dose d'un
///   aliment, qu'on peut laisser vide tant qu'on ne sait pas).
///
/// La plage porte le signe : `-5...5` autorise les valeurs négatives (un
/// ajustement peut retrancher de la dose), `0...30` ne les autorise pas.
struct StepperDose: View {

    @Binding private var valeur: Double?

    /// Bornes incluses. Une borne basse négative autorise de fait la
    /// saisie de valeurs négatives (ajustements).
    let plage: ClosedRange<Double>
    let pas: Double

    /// Titre de l'alerte de saisie (ex. « Dose d'insuline »).
    let titreSaisie: String

    /// Affiche explicitement le signe (`+1,5u` / `-0,5u`) — pertinent pour un
    /// ajustement ou une correction, pas pour une dose absolue.
    let afficheSigne: Bool

    /// Couleur de la valeur, dérivée de la valeur elle-même (orange pour un
    /// retrait, rouge pour un ajout…). `nil` → `.primary`.
    let couleur: (Double) -> Color

    /// `true` : une valeur ramenée à 0 repasse à `nil` (« — ») plutôt que
    /// d'afficher « 0u ». Utilisé pour la dose d'un aliment, où « pas de
    /// dose » et « dose nulle » sont la même chose.
    let zeroVautNil: Bool

    @State private var afficherSaisie = false
    @State private var texteSaisie = ""

    // MARK: - Inits

    init(
        valeur: Binding<Double?>,
        plage: ClosedRange<Double>,
        pas: Double = 0.5,
        titreSaisie: String = "Dose d'insuline",
        afficheSigne: Bool = false,
        zeroVautNil: Bool = true,
        couleur: @escaping (Double) -> Color = { _ in .primary }
    ) {
        self._valeur = valeur
        self.plage = plage
        self.pas = pas
        self.titreSaisie = titreSaisie
        self.afficheSigne = afficheSigne
        self.zeroVautNil = zeroVautNil
        self.couleur = couleur
    }

    init(
        valeur: Binding<Double>,
        plage: ClosedRange<Double>,
        pas: Double = 0.5,
        titreSaisie: String = "Dose d'insuline",
        afficheSigne: Bool = false,
        couleur: @escaping (Double) -> Color = { _ in .primary }
    ) {
        // Pont non-optionnel → optionnel : `nil` ne peut jamais remonter
        // (`zeroVautNil` est faux), la valeur reste donc toujours définie.
        self._valeur = Binding(
            get: { valeur.wrappedValue },
            set: { valeur.wrappedValue = $0 ?? 0 }
        )
        self.plage = plage
        self.pas = pas
        self.titreSaisie = titreSaisie
        self.afficheSigne = afficheSigne
        self.zeroVautNil = false
        self.couleur = couleur
    }

    // MARK: - Corps

    var body: some View {
        HStack {
            BoutonStepper(systemImage: "minus") { decrementer() }
                .disabled(!peutDecrementer)

            Spacer()

            Button {
                texteSaisie = valeur.map { formateBrut($0) } ?? ""
                afficherSaisie = true
            } label: {
                valeurAffichee
            }
            .buttonStyle(.plain)

            Spacer()

            BoutonStepper(systemImage: "plus") { incrementer() }
                .disabled(!peutIncrementer)
        }
        .alert(titreSaisie, isPresented: $afficherSaisie) {
            TextField("ex : \(formateBrut(exempleSaisie))", text: $texteSaisie)
                // `numbersAndPunctuation` et non `decimalPad` quand le négatif
                // est autorisé : le pavé décimal n'a pas de touche « - ».
                .keyboardType(plage.lowerBound < 0 ? .numbersAndPunctuation : .decimalPad)
            Button("OK") { appliquerSaisie() }
            Button("Annuler", role: .cancel) { texteSaisie = "" }
        } message: {
            Text("Entrez une valeur entre \(formateBrut(plage.lowerBound)) et \(formateBrut(plage.upperBound))")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(titreSaisie)
        .accessibilityValue(valeur.map { texteValeur($0) } ?? "non renseigné")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: incrementer()
            case .decrement: decrementer()
            @unknown default: break
            }
        }
    }

    @ViewBuilder
    private var valeurAffichee: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            if let v = valeur {
                Text(texteNombre(v))
                    .font(.title3.bold())
                    .foregroundStyle(couleur(v))
                    .contentTransition(.numericText())
                    // easeOut plutôt que spring : un spring overshoote, et
                    // avec `.contentTransition(.numericText())` cet overshoot
                    // affiche des valeurs intermédiaires fantômes.
                    .animation(.easeOut(duration: 0.2), value: v)
                Text("u")
                    .font(.body.bold())
                    .foregroundStyle(.secondary)
            } else {
                Text("—")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
    }

    // MARK: - Actions

    private var peutIncrementer: Bool { (valeur ?? 0) + pas <= plage.upperBound + 0.0001 }
    private var peutDecrementer: Bool { (valeur ?? 0) - pas >= plage.lowerBound - 0.0001 }

    private func incrementer() {
        guard peutIncrementer else { return }
        appliquer((valeur ?? 0) + pas)
    }

    private func decrementer() {
        guard peutDecrementer else { return }
        appliquer((valeur ?? 0) - pas)
    }

    private func appliquer(_ nouvelle: Double) {
        let bornee = min(max(nouvelle, plage.lowerBound), plage.upperBound)
        valeur = (zeroVautNil && bornee == 0) ? nil : bornee
    }

    private func appliquerSaisie() {
        let texte = texteSaisie
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        defer { texteSaisie = "" }
        guard let saisie = Double(texte) else {
            // Saisie vide ou illisible : efface la valeur quand « pas de
            // dose » est un état légitime, sinon on ne touche à rien.
            if zeroVautNil { valeur = nil }
            return
        }
        appliquer(saisie)
    }

    // MARK: - Formatage

    /// Valeur d'exemple du placeholder — une valeur « typique » dans la plage
    /// plutôt qu'une borne (« ex : 2.5 » parle mieux que « ex : 30 »).
    private var exempleSaisie: Double {
        plage.contains(2.5) ? 2.5 : plage.upperBound
    }

    /// Nombre nu, sans signe forcé — pour préremplir le champ de saisie et
    /// formater les bornes du message.
    private func formateBrut(_ v: Double) -> String {
        v == floor(v) ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    /// Nombre tel qu'affiché sur le stepper — avec signe explicite si demandé.
    private func texteNombre(_ v: Double) -> String {
        guard afficheSigne else { return formateBrut(v) }
        let magnitude = formateBrut(abs(v))
        if v < 0 { return "-\(magnitude)" }
        if v > 0 { return "+\(magnitude)" }
        return "0"
    }

    private func texteValeur(_ v: Double) -> String {
        "\(texteNombre(v)) unités"
    }
}

// MARK: - Aperçus

#Preview("Dose simple") {
    @Previewable @State var dose: Double = 4.5
    Form {
        Section("Dose du repas") {
            StepperDose(valeur: $dose, plage: 0...30)
        }
    }
    .formStyle(.grouped)
}

#Preview("Ajustement signé (négatif autorisé)") {
    @Previewable @State var ajustement: Double = -0.5
    Form {
        Section("Ajustement") {
            StepperDose(
                valeur: $ajustement,
                plage: -5...5,
                titreSaisie: "Valeur de l'ajustement",
                afficheSigne: true,
                couleur: { $0 < 0 ? .orange : ($0 > 0 ? .red : .secondary) }
            )
        }
    }
    .formStyle(.grouped)
}

#Preview("Dose optionnelle (aliment)") {
    @Previewable @State var dose: Double? = nil
    Form {
        Section("Dose") {
            StepperDose(valeur: $dose, plage: 0...30)
        }
    }
    .formStyle(.grouped)
}
