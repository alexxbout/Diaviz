//
//  SousPagesProfil.swift
//  diaviz
//

import CloudKit
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Insuline

/// Sous-page « Insuline » — types rapide/lente, durée d'action (DIA) et
/// intervalle minimum entre deux lentes.
struct SousPageInsuline: View {
    var body: some View {
        Form {
            SectionInsuline()
        }
        .formStyle(.grouped)
        .navigationTitle("Insuline")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Ratios

/// Sous-page « Ratios » — regroupe les trois familles de ratios, qui
/// répondent toutes à la même question (« combien d'insuline pour quoi ») :
/// glucides par moment, correction d'hyper (ISF), et ratios post-sport.
struct SousPageRatios: View {
    var body: some View {
        Form {
            SectionRatios()
            SectionRatioCorrection()
            SectionRatiosSport()
        }
        .formStyle(.grouped)
        .navigationTitle("Ratios")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Repas

/// Sous-page « Repas » — horaires de début des sections et réglages de
/// la remontée « Repas à revoir » sur l'accueil.
struct SousPageRepas: View {
    var body: some View {
        Form {
            SectionHorairesRepas()
            SectionRepasARevoirReglages()
            SectionNouvellesTendancesReglages()
        }
        .formStyle(.grouped)
        .navigationTitle("Repas")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Resucrage

/// Sous-page « Resucrage » — fenêtre d'affichage de la carte accueil.
struct SousPageResucrage: View {
    var body: some View {
        Form {
            SectionResucrageReglages()
        }
        .formStyle(.grouped)
        .navigationTitle("Resucrage")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Analyse du coucher

/// Sous-page « Analyse du coucher » — réglages de l'analyse basale (B1).
struct SousPageAnalyseCoucher: View {
    var body: some View {
        Form {
            SectionAnalyseCoucherReglages()
        }
        .formStyle(.grouped)
        .navigationTitle("Analyse du coucher")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Seuils glycémiques

/// Sous-page « Seuils glycémiques » — bornes hypo / hyper personnelles.
struct SousPageSeuils: View {
    var body: some View {
        Form {
            SectionSeuilsGlycemiques()
        }
        .formStyle(.grouped)
        .navigationTitle("Seuils glycémiques")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Données

/// Sous-page « Données » — outils de diagnostic de la source CGM, et
/// gestion (suppression) des données du hub.
struct SousPageDonnees: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(ProfilService.self) private var profilService

    /// État de la synchronisation iCloud, alimenté en continu par les
    /// événements CloudKit — la page se met donc à jour d'elle-même pendant
    /// qu'on la regarde.
    private var sync = SyncICloudService.shared

    /// Quel bouton a déclenché la confirmation — `nil` quand aucun n'est
    /// actif. Une seule alerte partagée plutôt que deux `@State Bool` :
    /// évite toute ambiguïté si les deux boutons étaient tapés coup sur
    /// coup.
    @State private var suppressionEnCours: TypeSuppression?

    /// Reset iCloud en cours — l'appel réseau CloudKit n'est pas instantané.
    @State private var resetICloudEnCours = false

    /// Compte-rendu du dernier reset iCloud (succès ou échec explicite).
    @State private var messageReset: String?

    /// Archive produite, prête à être partagée via la feuille système.
    @State private var archiveAPartager: FichierArchive?

    /// Fichier choisi pour l'import, en attente de confirmation — l'import
    /// écrase tout, il ne se déclenche jamais sur le seul choix du fichier.
    @State private var archiveAImporter: URL?

    @State private var afficherSelecteurImport = false

    /// Compte-rendu du dernier export ou import.
    @State private var messageArchive: String?

    var body: some View {
        Form {
            Section {
                NavigationLink("Mes données") {
                    PageInventaireDonnees()
                }
            } footer: {
                Text("Combien de repas, d'injections, de séances et de resucrages l'app contient, et depuis quand.")
            }

            Section {
                NavigationLink("Diagnostic HealthKit") {
                    VueDiagnosticHealthKit()
                }
            } footer: {
                Text("Vérifiez ce que l'app reçoit d'Apple Santé (autorisations, dernières glycémies importées).")
            }

            Section {
                if let activite = sync.activiteEnCours {
                    HStack {
                        Text(activite.libelle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        ProgressView()
                    }
                }

                ligneCompte("Dernier envoi vers iCloud", libelleDate(sync.dernierExport))
                ligneCompte("Dernière réception", libelleDate(sync.dernierImport))

                if let erreur = sync.derniereErreur {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dernière erreur")
                            .foregroundStyle(.red)
                        Text(erreur.message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                ligneCompte("Profil enregistré", profilService.profil.estValide ? "oui" : "non")
                ligneCompte("Lignes profil", "\(compte(ProfilUtilisateur.self))")
                ligneCompte("Changements de réglages", "\(compte(ChangementParametre.self))")
                ligneCompte("Glycémies", "\(compte(GlucoseReading.self))")
                ligneCompte("Repas", "\(compte(Repas.self))")
                ligneCompte("Injections", "\(compte(Injection.self))")
                ligneCompte("Activités sportives", "\(compte(ActiviteSportive.self))")
            } header: {
                Text("Synchronisation iCloud")
            } footer: {
                Text("""
                iCloud envoie les modifications par lots, quand le système \
                le décide : aucune API ne permet de forcer une \
                synchronisation ni de savoir ce qu'il reste à envoyer. Ces \
                dates sont celles des derniers transferts réellement \
                confirmés. Les compteurs indiquent ce qui est présent sur \
                cet appareil à cet instant — après une réinstallation, ils \
                montent au fur et à mesure de la réception. Pour une \
                sauvegarde dont vous maîtrisez le contenu, utilisez l'archive \
                ci-dessous.
                """)
            }

            Section {
                Button {
                    exporter()
                } label: {
                    Label("Exporter une archive", systemImage: "square.and.arrow.up")
                }

                Button {
                    afficherSelecteurImport = true
                } label: {
                    Label("Importer une archive", systemImage: "square.and.arrow.down")
                }

                if let messageArchive {
                    Text(messageArchive)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Sauvegarde locale")
            } footer: {
                Text("""
                Enregistre tout dans un fichier JSON : données du hub, \
                profil, et les réglages d'aliments (renommages, aliments \
                cachés, aliments récents) qui ne sont pas synchronisés avec \
                iCloud et seraient perdus à la désinstallation. Garde-le \
                hors de l'app — Fichiers, iCloud Drive, AirDrop. L'import \
                remplace tout le contenu actuel et se resynchronise ensuite \
                avec iCloud.
                """)
            }

            Section {
                if resetICloudEnCours {
                    HStack {
                        Text("Suppression en cours…")
                            .foregroundStyle(.secondary)
                        Spacer()
                        ProgressView()
                    }
                } else {
                    Button("Effacer mon historique", role: .destructive) {
                        suppressionEnCours = .historique
                    }
                    Button("Tout réinitialiser", role: .destructive) {
                        suppressionEnCours = .toutYComprisICloud
                    }
                }
                if let messageReset {
                    Text(messageReset)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Gestion des données")
            } footer: {
                Text("""
                **Effacer mon historique** supprime ce que vous avez saisi \
                (repas, injections, sport, resucrages…) et le retire aussi \
                d'iCloud. Votre profil, vos réglages d'aliments et vos \
                glycémies restent en place.

                **Tout réinitialiser** efface absolument tout, ici et sur \
                iCloud — profil, réglages et glycémies compris — pour \
                repartir d'un compte vierge. Les glycémies se ré-importeront \
                d'Apple Santé. Relance l'app juste après.
                """)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Données")
        .navigationBarTitleDisplayMode(.inline)
        // `alert` plutôt que `confirmationDialog` : deux dialogues de
        // confirmation cohabitent sur cette page (suppression et import), et
        // SwiftUI rend leur superposition imprévisible — le dialogue
        // apparaissait parfois centré comme une alerte, parfois non. Une
        // alerte est de toute façon la forme juste ici : décision binaire,
        // destructive et irréversible, exactement comme « Effacer contenu et
        // réglages » dans les Réglages iOS.
        .alert(
            titreConfirmation,
            isPresented: Binding(
                get: { suppressionEnCours != nil },
                set: { if !$0 { suppressionEnCours = nil } }
            )
        ) {
            Button("Annuler", role: .cancel) { }
            Button(libelleActionConfirmation, role: .destructive) {
                guard let cible = suppressionEnCours else { return }
                supprimer(cible)
            }
        } message: {
            Text(messageConfirmation)
        }
        .sheet(item: $archiveAPartager) { fichier in
            FeuillePartage(url: fichier.url)
        }
        .fileImporter(
            isPresented: $afficherSelecteurImport,
            allowedContentTypes: [.json]
        ) { resultat in
            switch resultat {
            case .success(let url):
                archiveAImporter = url
            case .failure(let erreur):
                messageArchive = "Lecture impossible : \(erreur.localizedDescription)"
            }
        }
        .alert(
            "Importer cette archive ?",
            isPresented: Binding(
                get: { archiveAImporter != nil },
                set: { if !$0 { archiveAImporter = nil } }
            )
        ) {
            Button("Annuler", role: .cancel) { }
            Button("Remplacer", role: .destructive) {
                if let url = archiveAImporter { importer(depuis: url) }
            }
        } message: {
            Text("""
            Le contenu actuel de l'app (données, profil, réglages \
            d'aliments) sera remplacé par celui de l'archive, ici et sur \
            iCloud. Action irréversible.
            """)
        }
    }

    // MARK: - Archive

    /// Écrit l'archive dans un fichier temporaire puis ouvre la feuille de
    /// partage. Passer par un fichier (plutôt que par des données en
    /// mémoire) permet à l'utilisateur de l'enregistrer **hors de l'app** —
    /// une copie restée dans le conteneur de l'app disparaîtrait avec elle
    /// à la désinstallation, ce qui lui retirerait tout intérêt.
    private func exporter() {
        do {
            let data = try ArchiveDonneesService.exporter(contexte: modelContext)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(ArchiveDonneesService.nomFichierExport())
            try data.write(to: url)
            archiveAPartager = FichierArchive(url: url)
            messageArchive = "Archive de \(mesure(data.count)) prête."
            ToastsService.shared.afficher(.donnees, titre: "Archive prête", detail: mesure(data.count))
        } catch {
            messageArchive = "Export impossible : \(error.localizedDescription)"
        }
    }

    private func importer(depuis url: URL) {
        // Les fichiers venant du sélecteur système sont hors du bac à sable
        // de l'app : sans cette autorisation explicite, la lecture échoue.
        let accesAccorde = url.startAccessingSecurityScopedResource()
        defer { if accesAccorde { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            try ArchiveDonneesService.importer(data, contexte: modelContext)
            messageArchive = "Archive importée. Les données se resynchronisent avec iCloud."
            ToastsService.shared.afficher(.donnees, titre: "Archive importée", detail: mesure(data.count))
        } catch {
            messageArchive = "Import impossible : \(error.localizedDescription)"
        }
        archiveAImporter = nil
    }

    private func mesure(_ octets: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(octets), countStyle: .file)
    }

    /// Row de diagnostic « libellé | valeur », valeur en gris à droite.
    private func ligneCompte(_ libelle: String, _ valeur: String) -> some View {
        HStack {
            Text(libelle)
            Spacer()
            Text(valeur)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// Nombre de lignes présentes localement pour un type du hub — reflet
    /// direct de ce que l'import CloudKit a effectivement descendu.
    private func compte<T: PersistentModel>(_ type: T.Type) -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<T>())) ?? 0
    }

    private func libelleDate(_ date: Date?) -> String {
        guard let date else { return "Aucun" }
        return date.formatted(.relative(presentation: .named))
    }

    private var titreConfirmation: String {
        switch suppressionEnCours {
        case .historique: "Effacer votre historique ?"
        case .toutYComprisICloud: "Tout réinitialiser ?"
        case nil: ""
        }
    }

    /// Le bouton de validation nomme l'action plutôt qu'un « Supprimer »
    /// générique : les deux confirmations n'effacent pas du tout la même
    /// chose, et c'est le dernier libellé lu avant de valider.
    private var libelleActionConfirmation: String {
        switch suppressionEnCours {
        case .historique: "Effacer l'historique"
        case .toutYComprisICloud: "Tout réinitialiser"
        case nil: ""
        }
    }

    private var messageConfirmation: String {
        switch suppressionEnCours {
        case .historique:
            "Repas, injections, activités sportives, resucrages, états et médications seront définitivement supprimés, ici et sur iCloud. Votre profil, vos réglages d'aliments et vos glycémies sont conservés. Action irréversible."
        case .toutYComprisICloud:
            "Toutes les données de l'app seront supprimées de cet appareil ET du stockage iCloud, glycémies, profil et réglages compris. Les glycémies se ré-importeront d'Apple Santé. Relance l'app juste après. Action irréversible."
        case nil:
            ""
        }
    }

    /// Supprime les entités du hub. Passe par `SuppressionDonneesService`,
    /// qui supprime objet par objet : un batch `delete(model:)` ne serait
    /// jamais exporté vers iCloud, et les données réapparaîtraient au
    /// lancement suivant.
    private func supprimer(_ cible: TypeSuppression) {
        switch cible {
        case .historique:
            SuppressionDonneesService.supprimerDonneesHub(contexte: modelContext)
            messageReset = "Historique effacé."

        case .toutYComprisICloud:
            Task { await resetComplet() }
        }
    }

    /// Efface tout localement puis supprime la zone CloudKit. L'ordre
    /// compte : on vide d'abord le local (sinon un export pourrait
    /// recréer la zone juste après sa suppression), puis on efface la zone
    /// côté serveur pour ne pas dépendre du bon vouloir de l'export.
    private func resetComplet() async {
        resetICloudEnCours = true
        messageReset = nil

        SuppressionDonneesService.supprimerTout(contexte: modelContext)

        do {
            try await SyncICloudService.supprimerZone()
            messageReset = "iCloud vidé. Relance l'app pour repartir proprement."
        } catch {
            let statut = await SyncICloudService.statutCompte()
            messageReset = statut == .available
                ? "Données locales supprimées, mais iCloud n'a pas répondu : \(error.localizedDescription)"
                : "Données locales supprimées. iCloud est indisponible sur cet appareil (compte non connecté ou restreint)."
        }

        resetICloudEnCours = false
    }

    private enum TypeSuppression {
        /// Les données saisies uniquement — profil, réglages et glycémies
        /// restent. Le cas courant : « je repars sur un historique propre ».
        case historique
        /// Absolument tout, local et iCloud. Pour retrouver un compte vierge.
        case toutYComprisICloud
    }
}

/// URL d'archive à partager. `Identifiable` pour piloter `.sheet(item:)`,
/// qui garantit que la feuille reçoit bien l'URL courante (contrairement à
/// `.sheet(isPresented:)`, qui peut capturer un état périmé).
private struct FichierArchive: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// Feuille de partage système — laisse l'utilisateur envoyer l'archive où
/// il veut : Fichiers, iCloud Drive, AirDrop, mail…
private struct FeuillePartage: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Aperçus

#if DEBUG
#Preview("Ratios") {
    NavigationStack { SousPageRatios() }
        .environment(ProfilService.mockAvecRatiosParMoment())
}

#Preview("Insuline") {
    NavigationStack { SousPageInsuline() }
        .environment(ProfilService.mockComplet())
}

#Preview("Repas") {
    NavigationStack { SousPageRepas() }
        .environment(ProfilService.mockComplet())
}
#endif
