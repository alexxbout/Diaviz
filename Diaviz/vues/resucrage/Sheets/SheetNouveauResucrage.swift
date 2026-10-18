//
//  SheetNouveauResucrage.swift
//  diaviz
//

import SwiftData
import SwiftUI

/// Sheet de création d'un resucrage — intention obligatoire, quantité de
/// glucides rapides au curseur, aliments (recherche, même moteur que
/// glucides pré-sport), glycémie cible optionnelle. Pas d'édition en V1
/// (créer/supprimer seulement) : un resucrage se corrige en le supprimant et
/// le re-créant, pas de flux d'édition dédié pour l'instant.
struct SheetNouveauResucrage: View {

    let onValider: (Resucrage) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// « Récents » de la recherche d'aliment, propres au resucrage — chargés
    /// à l'ouverture de la recherche (voir `chargerRecentsResucrage`).
    @State private var recentsResucrage: [ResultatRechercheAliment] = []

    @State private var intention: IntentionResucrage?
    @State private var date = Date()
    @State private var aliments: [Aliment] = []
    @State private var glycemieCibleTexte = ""
    @State private var afficherRechercheAliment = false
    /// Quantité de glucides rapides — `Double` pour le `Slider`, toujours un
    /// multiple de `pasGlucides` (donc entier une fois converti).
    @State private var glucidesRapides: Double

    init(onValider: @escaping (Resucrage) -> Void) {
        self.onValider = onValider
        let reglage = ProfilService.shared.profil.preferencesAvancees.glucidesResucrageRapideParDefaut
            ?? Self.glucidesRapidesParDefaut
        let borne = min(max(reglage, Self.glucidesMin), Self.glucidesMax)
        _glucidesRapides = State(initialValue: Double(borne))
    }

    /// Intention obligatoire — pas de valeur par défaut implicite, seul
    /// l'utilisateur sait pourquoi (voir doc Eraser S1).
    private var peutValider: Bool { intention != nil }

    var body: some View {
        NavigationStack {
            Form {
                sectionIntention
                sectionGlucidesRapides
                SectionAlimentsAjoutes(
                    titreSection: "Aliments",
                    footer: "Aliments pris pour ce resucrage.",
                    aliments: $aliments,
                    onAjouter: {
                        chargerRecentsResucrage()
                        afficherRechercheAliment = true
                    }
                )
                SectionDateHeure(date: $date)
                sectionCible
            }
            .formStyle(.grouped)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Resucrage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { confirmer() }
                        .disabled(!peutValider)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
        .sheet(isPresented: $afficherRechercheAliment) {
            SheetRechercheAlimentSimple(titre: "Resucrage", recents: recentsResucrage) { aliment in
                aliments.append(aliment)
            }
        }
    }

    // MARK: - Section intention
    //
    // Obligatoire — bouton Enregistrer désactivé tant que rien n'est choisi,
    // même pattern que la structure d'effort sport.
    private var sectionIntention: some View {
        Section {
            VStack(spacing: 8) {
                ForEach(IntentionResucrage.allCases, id: \.self) { valeur in
                    CarteRadioIntention(
                        intention: valeur,
                        selectionnee: intention == valeur
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            intention = valeur
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Text("Intention")
        }
    }

    // MARK: - Section glucides rapides
    //
    // Curseur de quantité pour le cas fréquent d'un resucrage standard (jus
    // de fruits, tablettes de glucose…) où le détail de l'aliment n'apporte
    // rien. Valeur de départ = réglage du profil (Réglages → Resucrage), 15 g
    // sans réglage. Enregistré comme un aliment générique « Glucides rapides ».
    //
    // **Exclusif des aliments détaillés** : dès qu'un aliment est ajouté, le
    // curseur est grisé et ne compte plus — sinon une quantité par défaut
    // serait enregistrée en plus de l'aliment réellement pris (glucides
    // comptés en double).
    private var sectionGlucidesRapides: some View {
        let remplace = !aliments.isEmpty
        return Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Glucides rapides")
                    Spacer()
                    Text("\(Int(glucidesRapides)) g")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Slider(
                    value: $glucidesRapides,
                    in: Double(Self.glucidesMin)...Double(Self.glucidesMax),
                    step: Double(Self.pasGlucides)
                ) {
                    Text("Glucides rapides")
                }
                .accessibilityValue("\(Int(glucidesRapides)) grammes")
            }
            .opacity(remplace ? 0.4 : 1)
            .disabled(remplace)
            .sensoryFeedback(.selection, trigger: Int(glucidesRapides))
        } header: {
            Text("Glucides")
        } footer: {
            Text(remplace
                 ? "Remplacés par les aliments ajoutés ci-dessous."
                 : "Enregistrés tels quels, sans détailler l'aliment. Pour préciser, ajoutez-le ci-dessous : il remplace cette quantité.")
        }
    }

    // MARK: - Section glycémie cible
    private var sectionCible: some View {
        Section {
            HStack {
                TextField("Optionnel", text: $glycemieCibleTexte)
                    .keyboardType(.numberPad)
                Text("mg/dL")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Glycémie cible")
        } footer: {
            Text("À renseigner si vous visez une valeur précise plutôt qu'un resucrage standard.")
        }
    }

    // MARK: - Récents propres au resucrage

    /// Aliments déjà pris lors de **resucrages passés**, du plus récent au
    /// plus ancien, sans doublon — pas ceux des repas (le jus d'orange d'un
    /// petit-déjeuner n'est pas un resucrage). Déduits des resucrages
    /// enregistrés plutôt que d'un historique séparé : rien de plus à
    /// persister ni à synchroniser.
    ///
    /// Seuls les aliments CIQUAL rejoignent la liste (la recherche de cette
    /// sheet est CIQUAL uniquement) ; le générique « Glucides rapides », sans
    /// id CIQUAL, en est exclu — le curseur le couvre déjà.
    private func chargerRecentsResucrage() {
        var descripteur = FetchDescriptor<Resucrage>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descripteur.fetchLimit = 50
        let passes = (try? modelContext.fetch(descripteur)) ?? []

        var vus = Set<Int>()
        recentsResucrage = passes
            .flatMap(\.aliments)
            .compactMap(\.idCiqualSource)
            .filter { vus.insert($0).inserted }
            .compactMap { CiqualService.shared.aliment(id: $0) }
            .filter { !AlimentsCachesService.shared.estCache($0.id) }
            .map { .ciqual($0) }
    }

    // MARK: - Actions

    private var glycemieCibleDouble: Double? {
        let trim = glycemieCibleTexte.trimmingCharacters(in: .whitespaces)
        return trim.isEmpty ? nil : Double(trim)
    }

    private func confirmer() {
        guard let intention else { return }
        // Aucun aliment détaillé → la quantité du curseur devient l'aliment
        // générique. Avec des aliments, le curseur est ignoré (voir
        // `sectionGlucidesRapides`).
        let enregistres = aliments.isEmpty
            ? [Aliment(
                emoji: "🍬",
                nom: "Glucides rapides",
                quantite: 1,
                glucides: Int(glucidesRapides),
                insuline: 0
            )]
            : aliments
        let resucrage = Resucrage(
            date: date,
            intention: intention,
            aliments: enregistres,
            glycemieCible: glycemieCibleDouble
        )
        onValider(resucrage)
        dismiss()
    }
}

extension SheetNouveauResucrage {
    /// Valeur de repli si le profil n'a rien réglé — 15g, dose standard
    /// d'un resucrage correctif (3 morceaux de sucre / un petit jus de fruits).
    static let glucidesRapidesParDefaut = 15
    /// Bornes et pas du curseur de glucides rapides.
    static let glucidesMin = 5
    static let glucidesMax = 50
    static let pasGlucides = 5
}

// MARK: - Aperçu

#if DEBUG
#Preview {
    SheetNouveauResucrage(onValider: { _ in })
}
#endif
