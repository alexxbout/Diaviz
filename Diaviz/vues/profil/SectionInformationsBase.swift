//
//  SectionInformationsBase.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Section « INFORMATIONS DE BASE » du formulaire profil — prénom
/// (requis) et poids (optionnel, pour normaliser les analyses
/// statistiques).
///
/// Auto-save : chaque frappe / pas de stepper appelle
/// `service.mettreAJour(_:)` immédiatement, conformément au pattern
/// Réglages d'iOS — pas de bouton « Enregistrer » global.
struct SectionInformationsBase: View {

    @Environment(ProfilService.self) private var service

    /// Buffer texte du poids — un `TextField` ne se binde pas
    /// directement à un `Double?`, donc on garde une chaîne locale et
    /// on synchronise dans les deux sens via `.onChange`.
    @State private var poidsTexte: String = ""

    var body: some View {
        Section("Informations de base") {
            // MARK: Prénom
            VStack(alignment: .leading, spacing: 4) {
                TextField("Votre prénom", text: bindingPrenom)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()

                if prenomVide {
                    Text("Requis")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            // MARK: Poids
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField("Poids", text: $poidsTexte)
                        .keyboardType(.decimalPad)
                        .onChange(of: poidsTexte) { _, nouveau in
                            appliquerPoids(nouveau)
                        }
                    Text("kg")
                        .foregroundStyle(.secondary)
                }

                Text("Utilisé pour normaliser les analyses statistiques")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            // Synchronisation initiale du buffer poids depuis le modèle.
            poidsTexte = formatePoids(service.profil.poidsKg)
        }
    }

    // MARK: - Bindings

    /// Binding direct vers `profil.prenom`. On lit la valeur du service
    /// et on délègue toute écriture à `mettreAJour` pour conserver
    /// l'auto-save.
    private var bindingPrenom: Binding<String> {
        Binding(
            get: { service.profil.prenom },
            set: { nouveau in
                service.mettreAJour { $0.prenom = nouveau }
            }
        )
    }

    private var prenomVide: Bool {
        service.profil.prenom
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    // MARK: - Helpers poids

    /// Applique le texte saisi au modèle. On accepte la virgule en
    /// remplacement du point (séparateur décimal français), et on
    /// nettoie le poids à `nil` si le champ est vide.
    private func appliquerPoids(_ texte: String) {
        let trim = texte.trimmingCharacters(in: .whitespaces)
        if trim.isEmpty {
            service.mettreAJour { $0.poidsKg = nil }
            return
        }
        let normalise = trim.replacingOccurrences(of: ",", with: ".")
        if let valeur = Double(normalise), valeur > 0 {
            service.mettreAJour { $0.poidsKg = valeur }
        }
        // Si la chaîne n'est pas un nombre valide, on ne propage rien
        // — l'utilisateur est en train de taper, on attend qu'il ait
        // fini.
    }

    /// Formatage pour affichage initial : entier sans décimale, sinon
    /// une décimale (« 78 » plutôt que « 78,0 »).
    private func formatePoids(_ valeur: Double?) -> String {
        guard let valeur else { return "" }
        return valeur == floor(valeur)
            ? String(format: "%.0f", valeur)
            : String(format: "%.1f", valeur).replacingOccurrences(of: ".", with: ",")
    }
}
